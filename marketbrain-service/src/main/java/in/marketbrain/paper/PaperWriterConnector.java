package in.marketbrain.paper;

import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.*;
import java.util.Arrays;
import java.util.Objects;
import java.util.Properties;

/** Dedicated connector: no automatic activation or general datasource fallback.
 * The default-off Telegram review configuration may explicitly construct it after deployment review.
 * Owns a dedicated connection, never the general application datasource.
 * Private route/HBA review and credential provisioning require separate acceptance.
 */
public final class PaperWriterConnector implements PaperLedgerStore.Connections {
    public static final String ROLE = "marketbrain_paper_review_writer";
    public enum Transport { PRIVATE_SAME_MACHINE, VERIFIED_TLS }
    public record Target(String host, int port, String database, long databaseOid, Transport transport, Path rootCertificate) {
        public Target {
            if (host == null || host.length() > 253 || !host.matches("[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?")
                    || host.contains("..") || port < 1 || port > 65535
                    || database == null || !database.matches("[a-z][a-z0-9_]{0,62}") || databaseOid <= 0
                    || transport == null
                    || (transport == Transport.VERIFIED_TLS && (rootCertificate == null || !rootCertificate.isAbsolute()))
                    || (transport == Transport.PRIVATE_SAME_MACHINE &&
                        (!java.util.Set.of("localhost", "127.0.0.1", "host.docker.internal").contains(host) || rootCertificate != null)))
                throw new IllegalArgumentException("Invalid writer target");
        }
    }
    /** Returns a fresh, caller-owned buffer; it will be erased, never logged. */
    @FunctionalInterface public interface SecretSource { char[] read() throws Exception; }
    @FunctionalInterface interface Dialer { Connection connect(String url, Properties properties) throws SQLException; }
    private final Target target;
    private final SecretSource secrets;
    private final boolean activationAuthorized;
    private final Dialer dialer;
    public PaperWriterConnector(Target target, SecretSource secrets, boolean activationAuthorized) {
        this(target, secrets, activationAuthorized, DriverManager::getConnection);
    }
    PaperWriterConnector(Target target, SecretSource secrets, boolean activationAuthorized, Dialer dialer) {
        this.target = Objects.requireNonNull(target); this.secrets = Objects.requireNonNull(secrets);
        this.activationAuthorized = activationAuthorized; this.dialer = Objects.requireNonNull(dialer);
    }
    static final String IDENTITY_SQL = """
        SELECT current_user, session_user, current_database(), d.oid::bigint,
               COALESCE((SELECT ssl FROM pg_catalog.pg_stat_ssl WHERE pid=pg_backend_pid()),false),
               r.rolcanlogin AND NOT (r.rolsuper OR r.rolcreatedb OR r.rolcreaterole OR r.rolinherit
                 OR r.rolreplication OR r.rolbypassrls)
                 AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m WHERE m.member=r.oid)
        FROM pg_catalog.pg_database d, pg_catalog.pg_roles r
        WHERE d.datname=current_database() AND r.rolname=current_user
        """;
    @Override public Connection open() throws SQLException {
        if (!activationAuthorized) throw new SQLException("Writer activation is disabled", "08001");
        char[] password = null; Properties properties = new Properties(); Connection connection = null;
        try {
            if (target.transport() == Transport.VERIFIED_TLS &&
                    (!Files.isRegularFile(target.rootCertificate()) || !Files.isReadable(target.rootCertificate())))
                throw new SQLException("Trust certificate unavailable");
            password = secrets.read();
            if (password == null || password.length < 32 || password.length > 256)
                throw new SQLException("Invalid credential");
            for (char ch : password) if (ch < 33 || ch > 126) throw new SQLException("Invalid credential");
            properties.setProperty("user", ROLE);
            properties.setProperty("password", new String(password));
            // Explicit policy, never an automatic downgrade from TLS after failure.
            properties.setProperty("sslmode", target.transport() == Transport.VERIFIED_TLS ? "verify-full" : "disable");
            properties.setProperty("gssEncMode", "disable");
            if (target.transport() == Transport.VERIFIED_TLS)
                properties.setProperty("sslrootcert", target.rootCertificate().toString());
            properties.setProperty("connectTimeout", "10");
            properties.setProperty("socketTimeout", "15");
            properties.setProperty("loginTimeout", "15");
            properties.setProperty("ApplicationName", "marketbrain-paper-review-writer");
            connection = dialer.connect("jdbc:postgresql://" + target.host() + ":" + target.port() + "/" + target.database(), properties);
            properties.clear(); Arrays.fill(password, '\0');
            connection.setReadOnly(true);
            try (Statement statement = connection.createStatement()) {
                statement.setQueryTimeout(5);
                try (ResultSet row = statement.executeQuery(IDENTITY_SQL)) {
                    if (!row.next() || !ROLE.equals(row.getString(1)) || !ROLE.equals(row.getString(2))
                            || !target.database().equals(row.getString(3)) || row.getLong(4) != target.databaseOid()
                            || (target.transport() == Transport.VERIFIED_TLS && !row.getBoolean(5))
                            || !row.getBoolean(6) || row.next())
                        throw new SQLException("Writer identity check failed");
                }
            }
            connection.setReadOnly(false);
            return connection;
        } catch (Exception failure) {
            if (connection != null) try { connection.close(); } catch (Exception ignored) { /* no raw exception logging */ }
            // Driver/secret-source exception messages or causes can contain credentials; deliberately omit them.
            throw new SQLException("Writer connection refused; review target, transport, custody and role gates", "08001");
        } finally {
            if (password != null) Arrays.fill(password, '\0');
            properties.clear();
        }
    }
}
