package in.marketbrain.paper;

import com.fasterxml.jackson.databind.MapperFeature;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.json.JsonMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.*;
import java.time.Instant;
import java.util.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;

/** Bounded PostgreSQL engineering adapter; deliberately NOT a bean, endpoint or production migration. */
public final class PaperPersistenceEngineering {
    public static final String VERSION = "PAPER_PERSISTENCE_ENGINEERING_V1";
    public static final int MAX_COMMANDS = 256;
    private static final String ZERO = "0".repeat(64);
    private static final JsonMapper JSON = JsonMapper.builder().findAndAddModules()
            .enable(MapperFeature.SORT_PROPERTIES_ALPHABETICALLY)
            .enable(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS)
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS).build();
    public enum Kind { APPROVE, FILL, CANCEL, EXPIRE }
    public record Command(String id, Instant at, Kind kind, Approval approval, Fill fill,
                          Quote quote, RiskPermit permit, String orderId) {
        public Command {
            require(id != null && id.matches("[A-Za-z0-9_.:-]{1,100}"), "Invalid command ID");
            Objects.requireNonNull(at); Objects.requireNonNull(kind);
            switch (kind) {
                case APPROVE -> require(approval != null && fill == null && quote != null && permit != null && orderId == null, "Approval payload");
                case FILL -> require(approval == null && fill != null && quote != null && permit != null && orderId == null, "Fill payload");
                case CANCEL -> require(approval == null && fill == null && quote == null && permit == null && orderId != null && orderId.matches("[A-Za-z0-9_.:-]{1,100}"), "Cancel payload");
                case EXPIRE -> require(approval == null && fill == null && quote == null && permit == null && orderId == null, "Expire payload");
            }
        }
    }
    @FunctionalInterface public interface Connections { Connection open() throws SQLException; }
    @FunctionalInterface interface BeforeCommit { void run(Connection connection) throws SQLException; }
    public record Receipt(long revision, boolean duplicate, Audit audit, String tailHash) {}
    private record Loaded(Account account, FixtureClock clock, long revision, String tail, Map<String, String> commands, Instant lastAt) {}
    private final Connections connections;
    private final String schema;
    private final Policy policy;
    private final BeforeCommit beforeCommit;

    public PaperPersistenceEngineering(Connections connections, String schema, Policy policy) {
        this(connections, schema, policy, c -> {});
    }
    PaperPersistenceEngineering(Connections connections, String schema, Policy policy, BeforeCommit beforeCommit) {
        this.connections = Objects.requireNonNull(connections);
        require(schema != null && schema.matches("paper_verify_[a-f0-9]{32}"), "Only uniquely named engineering schemas permitted");
        this.schema = schema; this.policy = Objects.requireNonNull(policy); this.beforeCommit = Objects.requireNonNull(beforeCommit);
    }

    /** Explicit new isolated schema, never IF NOT EXISTS and never touches legacy paper tables. */
    public void initialize() throws SQLException {
        try (Connection c = connections.open()) {
            c.setAutoCommit(false);
            try {
                configure(c);
                sql(c, "CREATE SCHEMA " + schema);
                sql(c, "CREATE TABLE " + schema + ".account (id SMALLINT PRIMARY KEY CHECK(id=1), policy TEXT NOT NULL, revision BIGINT NOT NULL CHECK(revision BETWEEN 0 AND 256), tail CHAR(64) NOT NULL, audit TEXT NOT NULL)");
                sql(c, "CREATE TABLE " + schema + ".command (seq BIGINT PRIMARY KEY CHECK(seq BETWEEN 1 AND 256), command_id VARCHAR(100) NOT NULL UNIQUE, payload TEXT NOT NULL CHECK(octet_length(payload)<=16384), previous CHAR(64) NOT NULL, hash CHAR(64) NOT NULL)");
                try (PreparedStatement s = c.prepareStatement("INSERT INTO " + schema + ".account VALUES (1, ?, 0, ?, ?)")) {
                    s.setString(1, encode(policy)); s.setString(2, ZERO);
                    s.setString(3, encode(new Account(policy, new FixtureClock(Instant.EPOCH)).audit())); s.executeUpdate();
                }
                c.commit();
            } catch (Exception e) { rollback(c, e); throw propagate(e); }
        }
    }

    /** Serializes ALL reads/writes on the singleton account row, then rebuilds and reconciles bounded history. */
    public Receipt execute(Command command) throws SQLException {
        Objects.requireNonNull(command);
        String payload = encode(command);
        require(payload.getBytes(StandardCharsets.UTF_8).length <= 16384, "Command exceeds bound");
        return transaction(command, payload);
    }
    public Receipt inspect() throws SQLException { return transaction(null, null); }

    private Receipt transaction(Command command, String payload) throws SQLException {
        try (Connection c = connections.open()) {
            c.setAutoCommit(false); c.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);
            try {
                configure(c);
                Loaded state = loadLocked(c);
                if (command == null) { Receipt r = new Receipt(state.revision, false, state.account.audit(), state.tail); c.commit(); return r; }
                String old = state.commands.get(command.id);
                if (old != null) {
                    require(old.equals(payload), "Command ID payload conflict");
                    Receipt r = new Receipt(state.revision, true, state.account.audit(), state.tail); c.commit(); return r;
                }
                require(state.revision < MAX_COMMANDS, "Command capacity reached; no eviction");
                require(state.lastAt == null || !command.at.isBefore(state.lastAt), "Command clock rollback");
                apply(state.account, state.clock, command);
                long next = state.revision + 1;
                String hash = chain(next, state.tail, payload);
                try (PreparedStatement s = c.prepareStatement("INSERT INTO " + schema + ".command VALUES (?, ?, ?, ?, ?)")) {
                    s.setLong(1, next); s.setString(2, command.id); s.setString(3, payload); s.setString(4, state.tail); s.setString(5, hash); s.executeUpdate();
                }
                Audit audit = state.account.audit();
                try (PreparedStatement s = c.prepareStatement("UPDATE " + schema + ".account SET revision=?, tail=?, audit=? WHERE id=1 AND revision=?")) {
                    s.setLong(1, next); s.setString(2, hash); s.setString(3, encode(audit)); s.setLong(4, state.revision);
                    require(s.executeUpdate() == 1, "Account revision changed");
                }
                beforeCommit.run(c); // Fault injection only; default is no-op. No external action may occur here.
                c.commit(); // Connection loss here is an UNKNOWN outcome: caller retries identical command ID/payload, never a new ID.
                return new Receipt(next, false, audit, hash);
            } catch (Exception e) { rollback(c, e); throw propagate(e); }
        }
    }

    private Loaded loadLocked(Connection c) throws SQLException {
        long revision; String tail, expectedAudit;
        try (PreparedStatement s = c.prepareStatement("SELECT policy, revision, tail, audit FROM " + schema + ".account WHERE id=1 FOR UPDATE"); ResultSet r = s.executeQuery()) {
            require(r.next(), "Account absent; never reseed automatically");
            require(encode(policy).equals(r.getString(1)), "Policy version/content mismatch");
            revision = r.getLong(2); tail = r.getString(3); expectedAudit = r.getString(4);
            require(revision >= 0 && revision <= MAX_COMMANDS && expectedAudit.length() <= 4_000_000, "Account bounds");
        }
        FixtureClock clock = new FixtureClock(Instant.EPOCH); Account account = new Account(policy, clock);
        long count = 0; String previous = ZERO; Map<String,String> ids = new HashMap<>(); Instant last = null;
        try (PreparedStatement s = c.prepareStatement("SELECT seq, command_id, payload, previous, hash FROM " + schema + ".command ORDER BY seq LIMIT 257"); ResultSet r = s.executeQuery()) {
            while (r.next()) {
                count++; require(count <= MAX_COMMANDS && r.getLong(1) == count, "Sequence gap or capacity violation");
                String payload = r.getString(3);
                require(payload.getBytes(StandardCharsets.UTF_8).length <= 16384, "Oversized saved command");
                require(previous.equals(r.getString(4)) && chain(count, previous, payload).equals(r.getString(5)), "Command hash chain mismatch");
                Command command = decode(payload);
                require(encode(command).equals(payload) && command.id.equals(r.getString(2)) && ids.put(command.id, payload) == null, "Noncanonical or conflicting saved command");
                require(last == null || !command.at.isBefore(last), "Saved command clock rollback");
                apply(account, clock, command); last = command.at; previous = r.getString(5);
            }
        }
        require(count == revision && previous.equals(tail), "Account and journal revision mismatch");
        require(encode(account.audit()).equals(expectedAudit), "Account reconciliation failed");
        return new Loaded(account, clock, revision, tail, ids, last);
    }
    static void apply(Account account, FixtureClock clock, Command command) {
        clock.set(command.at);
        switch (command.kind) {
            case APPROVE -> account.approve(command.approval, command.quote, command.permit);
            case FILL -> account.fill(command.fill, command.quote, command.permit);
            case CANCEL -> account.cancel(command.orderId);
            case EXPIRE -> account.expireDue();
        }
    }
    static String encode(Object value) {
        try { return JSON.writeValueAsString(value); } catch (Exception e) { throw new IllegalArgumentException("Cannot encode engineering record", e); }
    }
    static Command decode(String value) {
        try { return JSON.readValue(value, Command.class); } catch (Exception e) { throw new IllegalArgumentException("Invalid saved command", e); }
    }
    static String chain(long sequence, String previous, String payload) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest((VERSION + "\n" + sequence + "\n" + previous + "\n" + payload).getBytes(StandardCharsets.UTF_8))); }
        catch (Exception e) { throw new IllegalStateException(e); }
    }
    private static void configure(Connection c) throws SQLException {
        sql(c, "SET LOCAL lock_timeout='3s'"); sql(c, "SET LOCAL statement_timeout='10s'");
        sql(c, "SET LOCAL idle_in_transaction_session_timeout='15s'"); sql(c, "SET LOCAL synchronous_commit=on");
    }
    private static void sql(Connection c, String sql) throws SQLException { try (Statement s = c.createStatement()) { s.execute(sql); } }
    private static void rollback(Connection c, Exception cause) { try { c.rollback(); } catch (SQLException e) { cause.addSuppressed(e); } }
    private static SQLException propagate(Exception e) throws SQLException {
        if (e instanceof SQLException sql) return sql;
        if (e instanceof RuntimeException runtime) throw runtime;
        return new SQLException("Paper persistence failure", e);
    }
    private static void require(boolean condition, String message) { if (!condition) throw new IllegalArgumentException(message); }
}
