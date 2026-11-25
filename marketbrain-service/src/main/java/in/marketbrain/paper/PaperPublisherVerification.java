package in.marketbrain.paper;
import java.sql.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperAccountEngineering.*;
import static in.marketbrain.paper.PaperLedgerVerification.*;
import static in.marketbrain.paper.PaperLedgerVerification.eq;


/** Disposable PostgreSQL fixture only; no production connection, passwords or real messaging. */
final class PaperPublisherVerification {
    static final String LOGIN="\""+PaperPaytmReviewPublisher.ROLE+"\"",STRANGER="paper_publish_stranger_fixture";
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
        try(var c=connect(schema)) {
            var receipt=PaperPublisherInstallation.run(c,target(c,schema),PaperPublisherInstallation.Mode.INSTALL_DISABLED);
            if(!receipt.committed()||receipt.loginEnabled())throw new AssertionError("Installer did not leave disabled roles");
        }
        if(number(schema,"SELECT count(*) FROM pg_roles WHERE rolname IN ('marketbrain-paper-publisher','marketbrain-paper-publisher-helper') AND rolcanlogin")!=0)
            throw new AssertionError("Installer enabled login");
        disabledInstallVerified=true;
        // ONLY the disposable fixture enables its synthetic login; production engine has no password API.
        sql(schema,"ALTER ROLE "+LOGIN+" LOGIN PASSWORD 'isolated_fixture_only'; CREATE ROLE "+STRANGER+" LOGIN PASSWORD 'isolated_fixture_only'; GRANT USAGE ON SCHEMA "+PaperWriterVerification.schema(schema)+" TO "+STRANGER);
    }
    boolean disabledInstallVerified;
    static PaperPublisherInstallation.Target target(Connection c,String schema)throws Exception {
        try(var s=c.createStatement();var r=s.executeQuery("SELECT current_database(),oid::bigint FROM pg_database WHERE datname=current_database()")) {
            r.next();return new PaperPublisherInstallation.Target(r.getString(1),r.getLong(2),schema);
        }
    }
    static void wrongTarget(String base)throws Exception {
        try(var c=connect("public")) {
            var t=target(c,schema(base));
            reject(()->PaperPublisherInstallation.run(c,new PaperPublisherInstallation.Target(t.database(),t.databaseOid()+1,t.schema()),PaperPublisherInstallation.Mode.INSTALL_DISABLED));
            eq(number("public","SELECT count(*) FROM pg_roles WHERE rolname='marketbrain-paper-publisher'"),0L);
        }
    }
    static void rehearsal(String base,boolean failAfterCreation)throws Exception {
        String schema=schema(base+(failAfterCreation?"failure":"rehearsal"));PaperStorageVerification.init(schema);
        if(failAfterCreation)sql(schema,"ALTER TABLE paper_approval_delivery DROP COLUMN message_id CASCADE");
        try(var c=connect(schema)) {
            var t=target(c,schema);
            if(failAfterCreation)reject(()->PaperPublisherInstallation.run(c,t,PaperPublisherInstallation.Mode.INSTALL_DISABLED));
            else eq(PaperPublisherInstallation.run(c,t,PaperPublisherInstallation.Mode.REHEARSE_ROLLBACK).status(),"PUBLISHER_INSTALL_REHEARSED_ROLLED_BACK");
        }
        eq(number(schema,"SELECT count(*) FROM pg_roles WHERE rolname IN ('marketbrain-paper-publisher','marketbrain-paper-publisher-helper')"),0L);
        eq(number(schema,"SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='"+schema+"' AND p.proname LIKE 'paper_publish_%'"),0L);
    }
    void reentryDenied()throws Exception {
        try(var c=connect(schema)){var t=target(c,schema);reject(()->PaperPublisherInstallation.run(c,t,PaperPublisherInstallation.Mode.INSTALL_DISABLED));}
        try(var c=connection(false)){PaperPaytmReviewPublisher.verifyRole(c);}
    }
    Proposal proposal(int n,String kind){String id="PAYTM_TEST_"+String.format("%032x",n)+"_"+kind;return new Proposal(id,1,1,0,111,222,new Approval(id,id,"FIXTURE",Side.BUY,1,10000,9950,10050,0,T,T.plusSeconds(100)),PaperReviewTestPolicy.paytmPolicy().id());}
    void denied(String sql,boolean stranger)throws Exception {boolean denied=false;try(var c=connection(stranger);var s=c.createStatement()){s.execute(sql);}catch(SQLException expected){denied=true;}if(!denied)throw new AssertionError("Unexpected database authority");}
    void unchanged()throws Exception{PaperApprovalVerification.unchanged(schema);}
}
