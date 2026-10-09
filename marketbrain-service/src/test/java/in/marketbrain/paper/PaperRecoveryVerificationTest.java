package in.marketbrain.paper;

import java.sql.SQLException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;

class PaperRecoveryVerificationTest {
    @ParameterizedTest @ValueSource(strings={"public;drop table x","../other","x\"x","UPPER","","a b"})
    void rejectsUnsafeIdentifiers(String id){assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.identifier(id));}
    @Test void quotesAllowlistedIdentifier(){assertEquals("\"paper_verify_123\"",PaperRecoveryVerification.identifier("paper_verify_123"));assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.identifier(null));assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.identifier("a".repeat(64)));}
    @Test void onlyPermissionSqlStateCountsAsDenial()throws Exception{
        PaperRecoveryVerification.denied(()->{throw new SQLException("fixture","42501");});
        for(String state:new String[]{"42P01","42601","08001","23502",null})assertThrows(SQLException.class,()->PaperRecoveryVerification.denied(()->{throw new SQLException("fixture",state);}));
        assertThrows(AssertionError.class,()->PaperRecoveryVerification.denied(()->{}));
    }
    @Test void cannotConnectToApplicationDatabase(){assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.connection("marketbrain","paper_verify_"+"a".repeat(32),false));assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.connection("paper_restore","public",false));}
    @Test void invalidEntrypointDoesNotReachJdbc(){assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.main(new String[]{"--prepare","public"}));assertThrows(IllegalArgumentException.class,()->PaperRecoveryVerification.main(new String[]{"--live","paper_verify_"+"a".repeat(32)}));}
    @Test void auditProjectionExcludesSecretsAndIdentity()throws Exception{
        String sql=PaperLedgerVerification.resource("/paper/approval-audit-v1.sql");
        assertTrue(sql.contains("SELECT portfolio_id, cash, reserved, revision"));
        assertTrue(sql.contains("(p.receipt IS NOT NULL) AS reviewed"));
        for(String field:new String[]{"encrypted_tokens","token_hash","fingerprint","probe","recipient_hash","telegram_user_id","telegram_chat_id","payload","SELECT *","GRANT ALL"})assertFalse(sql.contains(field),field);
    }
}
