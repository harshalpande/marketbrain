package in.marketbrain.paper;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.nio.charset.StandardCharsets;
import java.sql.SQLException;

class PaperPublisherAccessPlanTest {
    @Test void preservesBomAndExistingRulesAndPlacesAllowBeforeDenials() throws Exception {
        String existing="host all all 127.0.0.1/32 scram-sha-256\r\n";
        byte[] original=("\uFEFF"+existing).getBytes(StandardCharsets.UTF_8);
        String result=new String(PaperPublisherAccessPlan.candidate(original,"127.0.0.1"),StandardCharsets.UTF_8);
        assertTrue(result.startsWith("\uFEFF# BEGIN"));
        assertTrue(result.endsWith(existing));
        assertTrue(result.indexOf("127.0.0.1/32 scram-sha-256")<result.indexOf("0.0.0.0/0 reject"));
        assertTrue(result.contains("::/0 reject\r\n"));
        assertThrows(SQLException.class,()->PaperPublisherAccessPlan.candidate(result.getBytes(StandardCharsets.UTF_8),"127.0.0.1"));
    }
    @Test void refusesDifferentRouteAndEmptyOrOversizedInput(){
        assertThrows(SQLException.class,()->PaperPublisherAccessPlan.candidate(new byte[]{32},"10.0.0.1"));
        assertThrows(SQLException.class,()->PaperPublisherAccessPlan.candidate(new byte[0],"127.0.0.1"));
        assertThrows(SQLException.class,()->PaperPublisherAccessPlan.candidate(new byte[1048577],"127.0.0.1"));
    }
}
