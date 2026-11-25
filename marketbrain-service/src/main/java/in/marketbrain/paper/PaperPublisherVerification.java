package in.marketbrain.paper;
import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Disposable PostgreSQL fixture only; no production connection, passwords or real messaging. */
final class PaperPublisherVerification {
    static final String LOGIN="\""+PaperPaytmReviewPublisher.ROLE+"\"",HELPER="paper_publish_helper_fixture",STRANGER="paper_publish_stranger_fixture";
    static String schema(String base){return "paper_verify_"+UUID.nameUUIDFromBytes(("publisher:"+base).getBytes(java.nio.charset.StandardCharsets.UTF_8)).toString().replace("-","");}
    final String schema;final PaperApprovalVerification.Time clock=new PaperApprovalVerification.Time();final AtomicInteger sends=new AtomicInteger();
    final PaperApprovalDelivery delivery;boolean uncertain;
    PaperPublisherVerification(String base,boolean install)throws Exception {
        this.schema=schema(base);if(install)install();
        var review=new PaperApprovalReview(()->connection(false),p->{throw new AssertionError("No quote at publication");},clock,PaperReviewTestPolicy.paytmPolicy());
        delivery=PaperApprovalDelivery.restrictedPublisher(()->connection(false),review,(p,t)->{sends.incrementAndGet();if(uncertain)throw new java.io.IOException("synthetic lost acknowledgement");return "123";},clock,PaperStorageVerification.KEY);
    }
    Connection connection(boolean stranger)throws SQLException {
        var c=DriverManager.getConnection("jdbc:postgresql://db:5432/paper_fixture?connectTimeout=5&socketTimeout=20",stranger?STRANGER:PaperPaytmReviewPublisher.ROLE,"isolated_fixture_only");c.setSchema(schema);return c;
    }
    void install()throws Exception {
        PaperStorageVerification.init(schema);sql(schema,"INSERT INTO telegram_binding(binding_key,telegram_user_id,telegram_chat_id) VALUES('PRIMARY',111,222)");PaperStorageVerification.bind(schema);
        String quoted=PaperWriterVerification.schema(schema);
        try(var c=connect(schema);var s=c.createStatement()) {c.setAutoCommit(false);try {
            s.execute("CREATE ROLE "+LOGIN+" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD 'isolated_fixture_only'; CREATE ROLE "+HELPER+" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS; CREATE ROLE "+STRANGER+" LOGIN PASSWORD 'isolated_fixture_only'");
            s.execute("REVOKE ALL ON SCHEMA "+quoted+" FROM PUBLIC; REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "+quoted+" FROM PUBLIC; GRANT USAGE ON SCHEMA "+quoted+" TO "+LOGIN+","+HELPER+","+STRANGER);
            String readers="paper_approval_proposal,paper_approval_token,paper_approval_delivery,paper_approval_key_binding,telegram_binding,paper_portfolio,paper_ledger_account,paper_ledger_command,paper_ledger_position,instrument";
            s.execute("GRANT SELECT ON "+readers+" TO "+LOGIN+","+HELPER);
            s.execute("GRANT INSERT ON paper_approval_proposal,paper_approval_token,paper_approval_delivery TO "+HELPER+"; GRANT UPDATE(state,attempt_id,attempted_at,message_id) ON paper_approval_delivery TO "+HELPER+"; GRANT UPDATE(id) ON paper_portfolio TO "+HELPER+"; GRANT UPDATE(portfolio_id) ON paper_ledger_account TO "+HELPER+"; GRANT UPDATE(binding_key) ON telegram_binding TO "+HELPER);
            s.execute(resource("/paper/approval-publisher-v1.sql").replace("__SCHEMA__",quoted).replace("__POLICY_JSON__",encode(PaperReviewTestPolicy.paytmPolicy()).replace("'","''")));
            s.execute("GRANT CREATE ON SCHEMA "+quoted+" TO "+HELPER);
            for(String signature:List.of("paper_publish_enqueue(text,text,text,text,text,timestamptz)","paper_publish_lock(text)","paper_publish_transition(text,text,text,timestamptz,text)")){
                s.execute("ALTER FUNCTION "+signature+" OWNER TO "+HELPER+"; GRANT EXECUTE ON FUNCTION "+signature+" TO "+LOGIN);
            }
            s.execute("REVOKE CREATE ON SCHEMA "+quoted+" FROM "+HELPER);c.commit();
        }catch(Exception failure){c.rollback();throw failure;}}
    }
    Proposal proposal(int n,String kind){String id="PAYTM_TEST_"+String.format("%032x",n)+"_"+kind;return new Proposal(id,1,1,0,111,222,new Approval(id,id,"FIXTURE",Side.BUY,1,10000,9950,10050,0,T,T.plusSeconds(100)),PaperReviewTestPolicy.paytmPolicy().id());}
    void denied(String sql,boolean stranger)throws Exception {boolean denied=false;try(var c=connection(stranger);var s=c.createStatement()){s.execute(sql);}catch(SQLException expected){denied=true;}if(!denied)throw new AssertionError("Unexpected database authority");}
    void unchanged()throws Exception{PaperApprovalVerification.unchanged(schema);}
}
