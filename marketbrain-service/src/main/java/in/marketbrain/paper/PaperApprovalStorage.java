package in.marketbrain.paper;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Service;
import javax.sql.DataSource;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.*;
import java.util.*;
import static in.marketbrain.paper.PaperLedgerStore.*;

/** Storage/key setup only. Does not register an approval callback, sender or command authority. */
@Service
public final class PaperApprovalStorage implements ApplicationRunner {
    private static final String DOMAIN="MARKETBRAIN_PAPER_DELIVERY_KEY_V1";
    private final Connections connections;
    private final boolean enabled;
    private final String mode,path;
    private volatile boolean initialized;
    public PaperApprovalStorage(DataSource source,
            @Value("${marketbrain.paper.approval-storage-enabled:false}") boolean enabled,
            @Value("${marketbrain.paper.approval-key-file:}") String path,
            @Value("${marketbrain.execution-mode:PAPER}") String mode){
        this.connections=source::getConnection;this.enabled=enabled;this.path=path;this.mode=mode;
    }
    public record Status(String version,String status,boolean databaseWritesPerformed,
                         boolean notificationEnabled,boolean actionExecutionEnabled,boolean liveExecutionEnabled){}
    @Override public void run(ApplicationArguments args){
        if(!enabled||!"PAPER".equals(mode))return;
        byte[] key=null;
        try{key=readKey(path);bind(connections,key);initialized=true;}
        catch(Exception blocked){initialized=false;} // Do not break unrelated collection, expose secrets or silently replace a key.
        finally{if(key!=null)Arrays.fill(key,(byte)0);}
    }
    public Status status(){
        if(!enabled||!"PAPER".equals(mode))return result("DISABLED");
        if(!initialized)return result("STORAGE_SETUP_BLOCKED");
        byte[] key=null;
        try{key=readKey(path);verify(connections,key);return result("STORAGE_KEY_VERIFIED_ACTIONS_DISABLED");}
        catch(Exception blocked){return result("STORAGE_KEY_REVIEW_REQUIRED");}
        finally{if(key!=null)Arrays.fill(key,(byte)0);}
    }
    private static Status result(String status){return new Status("PAPER_APPROVAL_STORAGE_V1",status,false,false,false,false);}
    static byte[] readKey(String name)throws Exception{
        Path file=Path.of(name);
        if(!file.isAbsolute()||!Files.isRegularFile(file,LinkOption.NOFOLLOW_LINKS))throw new IllegalArgumentException("Key file unavailable");
        byte[] encoded;
        try(var stream=Files.newInputStream(file,LinkOption.NOFOLLOW_LINKS)){encoded=stream.readNBytes(129);}
        try{
            if(encoded.length>128)throw new IllegalArgumentException("Invalid key file");
            String value=new String(encoded,StandardCharsets.US_ASCII).strip();
            if(!value.matches("[A-Za-z0-9+/]{43}="))throw new IllegalArgumentException("Invalid key encoding");
            byte[] key=Base64.getDecoder().decode(value);validate(key);return key;
        }finally{Arrays.fill(encoded,(byte)0);}
    }
    private static void validate(byte[] key){
        if(key==null||key.length!=32)throw new IllegalArgumentException("256-bit key required");
        int any=0;for(byte b:key)any|=b;if(any==0)throw new IllegalArgumentException("Zero key forbidden");
    }
    static String fingerprint(byte[] key){validate(key);try{var hash=MessageDigest.getInstance("SHA-256");hash.update(DOMAIN.getBytes(StandardCharsets.UTF_8));return HexFormat.of().formatHex(hash.digest(key));}catch(Exception failure){throw new IllegalStateException("Key digest unavailable");}}
    static void bind(Connections connections,byte[] key)throws Exception{
        validate(key);
        try(var c=connections.open()){
            PaperApprovalReview.begin(c);
            try{
                try(var s=statement(c,"SELECT pg_advisory_xact_lock(804192831)")){s.execute();}
                if(existing(c,key)){c.commit();return;}
                for(String table:List.of("paper_approval_proposal","paper_approval_token","paper_approval_delivery")){
                    try(var s=statement(c,"SELECT 1 FROM "+table+" LIMIT 1");var rows=s.executeQuery()){
                        if(rows.next())throw new IllegalArgumentException("Unbound existing evidence requires review");
                    }
                }
                update(c,"INSERT INTO paper_approval_key_binding(id,fingerprint,probe) VALUES(1,?,?)",fingerprint(key),new PaperApprovalDelivery.Vault(key).seal(DOMAIN,DOMAIN));
                c.commit();
            }catch(Exception failure){c.rollback();throw failure;}
        }
    }
    static void verify(Connections connections,byte[] key)throws Exception{
        validate(key);
        try(var c=connections.open()){
            c.setReadOnly(true);c.setAutoCommit(false);
            try{if(!existing(c,key))throw new IllegalArgumentException("Key binding absent");c.commit();}
            catch(Exception failure){c.rollback();throw failure;}
        }
    }
    private static boolean existing(Connection c,byte[] key)throws Exception{
        try(var s=statement(c,"SELECT fingerprint,probe FROM paper_approval_key_binding WHERE id=1");var row=s.executeQuery()){
            if(!row.next())return false;
            if(!fingerprint(key).equals(row.getString(1))||!DOMAIN.equals(new PaperApprovalDelivery.Vault(key).open(row.getString(2),DOMAIN)))throw new IllegalArgumentException("Key binding mismatch");
            return true;
        }
    }
}
