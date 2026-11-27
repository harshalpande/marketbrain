package in.marketbrain.paper;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.*;
import java.util.*;

/** Build an exact candidate in memory for the locally hosted PostgreSQL deployment. */
final class PaperPublisherAccessPlan {
    private static final String ROLE = "marketbrain-paper-publisher";

    static byte[] candidate(byte[] original, String source) throws Exception {
        if (!"127.0.0.1".equals(source)) throw new SQLException("Unexpected Docker source address");
        if (original.length == 0 || original.length > 1048576) throw new SQLException("Unsupported HBA size");
        String text = StandardCharsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(original)).toString();
        if (text.contains(ROLE) || text.indexOf('\0') >= 0) throw new SQLException("Existing publisher configuration or invalid HBA");
        String newline = text.contains("\r\n") ? "\r\n" : "\n";
        String prefix = String.join(newline,
            "# BEGIN MARKETBRAIN PAPER PUBLISHER",
            "host marketbrain " + ROLE + " 127.0.0.1/32 scram-sha-256",
            "local all,replication " + ROLE + " reject",
            "host all,replication " + ROLE + " 0.0.0.0/0 reject",
            "host all,replication " + ROLE + " ::/0 reject",
            "# END MARKETBRAIN PAPER PUBLISHER", "");
        int offset = text.startsWith("\uFEFF") ? 1 : 0;
        return (text.substring(0,offset) + prefix + text.substring(offset)).getBytes(StandardCharsets.UTF_8);
    }

    static Map<String,Object> observe(Connection c) throws Exception {
        String sql = """
            SELECT host(inet_client_addr()),current_database(),
              (SELECT system_identifier::text FROM pg_catalog.pg_control_system()),
              NOT EXISTS(SELECT FROM pg_catalog.pg_hba_file_rules WHERE error IS NOT NULL
                OR 'marketbrain-paper-publisher'=ANY(user_name)),
              pg_catalog.pg_read_binary_file(current_setting('hba_file'),0,1048577)
            """;
        try (var statement = c.createStatement()) {
            statement.setQueryTimeout(10);
            try (var row = statement.executeQuery(sql)) {
                if (!row.next() || !"marketbrain".equals(row.getString(2))
                    || !"7679149914381758260".equals(row.getString(3)) || !row.getBoolean(4))
                    throw new SQLException("HBA plan preconditions changed");
                byte[] original = row.getBytes(5);
                byte[] proposed = candidate(original,row.getString(1));
                var digest = MessageDigest.getInstance("SHA-256");
                var hex = HexFormat.of().withUpperCase();
                return Map.of("status","PUBLISHER_HBA_PLAN_READY","scope","LOOPBACK_IPV4",
                    "originalHash",hex.formatHex(digest.digest(original)),
                    "candidateHash",hex.formatHex(digest.digest(proposed)));
            }
        }
    }
}
