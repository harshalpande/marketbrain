package in.marketbrain.paper;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.sql.*;
import java.time.Clock;
import java.util.*;
import static in.marketbrain.paper.PaperApprovalReview.*;
import static in.marketbrain.paper.PaperLedgerStore.*;
import static in.marketbrain.paper.PaperPersistenceEngineering.encode;

/** Internal review-only delivery. No bean, scheduler or publication endpoint.
 * A send can be uncertain. Never automatically resend an attempted message. */
public final class PaperApprovalDelivery {
    @FunctionalInterface public interface Sender { String send(Proposal proposal,Tokens tokens) throws Exception; }
    private final Connections connections;
    private final PaperApprovalReview review;
    private final Sender sender;
    private final Clock clock;
    private final Vault vault;
    private final boolean restricted;
    public PaperApprovalDelivery(Connections connections,PaperApprovalReview review,Sender sender,Clock clock,byte[] encryptionKey) {
        this(connections,review,sender,clock,encryptionKey,false);
    }
    private PaperApprovalDelivery(Connections connections,PaperApprovalReview review,Sender sender,Clock clock,byte[] encryptionKey,boolean restricted) {
        this.connections=Objects.requireNonNull(connections);this.review=Objects.requireNonNull(review);
        this.sender=Objects.requireNonNull(sender);this.clock=Objects.requireNonNull(clock);this.vault=new Vault(encryptionKey);
        this.restricted=restricted;
    }
    public static PaperApprovalDelivery restrictedPublisher(Connections connections,PaperApprovalReview review,Sender sender,Clock clock,byte[] key) {
        return new PaperApprovalDelivery(connections,review,sender,clock,key,true);
    }
    /** Same id + exact proposal reconciles an uncertain enqueue, never issues new tokens. */
    public String enqueue(Proposal proposal)throws SQLException {
        return enqueueBatch(List.of(proposal)).getFirst();
    }
    /** At most three review fixtures, committed together. Deterministic locking avoids reversed-batch deadlocks. */
    public List<String> enqueueBatch(List<Proposal> proposals)throws SQLException {
        if(proposals==null||proposals.isEmpty()||proposals.size()>3||proposals.stream().anyMatch(Objects::isNull)
                ||proposals.stream().map(Proposal::id).distinct().count()!=proposals.size())
            throw new IllegalArgumentException("Bounded distinct review batch required");
        var batch=proposals.stream().sorted(Comparator.comparing(Proposal::id)).toList();
        try(var c=connections.open()){begin(c);try{
            var states=new LinkedHashMap<String,String>();
            for(var proposal:batch) states.put(proposal.id(),enqueue(c,proposal));
            c.commit();return proposals.stream().map(p->states.get(p.id())).toList();
        }catch(Exception failure){c.rollback();throw failure;}}
    }
    private String enqueue(Connection c,Proposal proposal)throws SQLException {
            if(restricted) {
                var random=new SecureRandom();byte[] a=new byte[32],b=new byte[32];random.nextBytes(a);random.nextBytes(b);
                var tokens=new Tokens(Base64.getUrlEncoder().withoutPadding().encodeToString(a),Base64.getUrlEncoder().withoutPadding().encodeToString(b));
                try(var s=statement(c,"SELECT paper_publish_enqueue(?,?,?,?,?,?)",encode(proposal),encode(PaperReviewTestPolicy.paytmPolicy()),
                        hash(tokens.accept()),hash(tokens.reject()),vault.seal(encode(tokens),proposal.id()),Timestamp.from(clock.instant()));var r=s.executeQuery()) {
                    if(!r.next())throw new SQLException("Publisher response absent");return r.getString(1);
                }
            }
            // Serialize identical publishers without locking all portfolios. Collision only causes waiting.
            try(var s=statement(c,"SELECT pg_advisory_xact_lock(hashtextextended(?,0))",proposal.id())){s.execute();}
            binding(c,proposal.userId(),proposal.chatId(),true);
            try(var s=statement(c,"SELECT p.payload,d.state FROM paper_approval_proposal p JOIN paper_approval_delivery d ON d.proposal_id=p.id WHERE p.id=?",proposal.id());var r=s.executeQuery()){
                if(r.next()){if(!encode(proposal).equals(r.getString(1)))throw new IllegalArgumentException("Proposal identity conflict");return r.getString(2);}
            }
            Tokens tokens=review.issue(c,proposal);
            String sealed=vault.seal(encode(tokens),proposal.id());
            update(c,"INSERT INTO paper_approval_delivery(proposal_id,encrypted_tokens,state,created_at) VALUES(?,?,'PENDING',?)",proposal.id(),sealed,Timestamp.from(clock.instant()));
            return "PENDING";
    }
    /** One explicitly selected proposal, no full-table poll or unbounded worker queue. */
    public String dispatch(String proposalId)throws SQLException {
        Proposal proposal;Tokens tokens;String attempt=UUID.randomUUID().toString();
        try(var c=connections.open()){begin(c);try{
            if(restricted)try(var s=statement(c,"SELECT paper_publish_lock(?)",proposalId)){s.execute();}
            try(var s=statement(c,"SELECT p.payload,p.payload_hash,d.encrypted_tokens,d.state FROM paper_approval_delivery d JOIN paper_approval_proposal p ON p.id=d.proposal_id WHERE d.proposal_id=?"+(restricted?"":" FOR UPDATE OF d"),proposalId);var r=s.executeQuery()){
                if(!r.next())throw new IllegalArgumentException("Delivery absent");
                String state=r.getString(4);if(!state.equals("PENDING")){c.commit();return state;}
                if(!hash(r.getString(1)).equals(r.getString(2)))throw new IllegalArgumentException("Proposal corruption");
                proposal=decode(r.getString(1),Proposal.class);
                if(!proposal.id().equals(proposalId))throw new IllegalArgumentException("Proposal mismatch");
                String blocked=null;
                try{binding(c,proposal.userId(),proposal.chatId(),!restricted);}catch(IllegalArgumentException denied){blocked="REVOKED";}
                if(clock.instant().isBefore(proposal.terms().createdAt())||!clock.instant().isBefore(proposal.terms().expiresAt()))blocked="EXPIRED";
                tokens=null;
                if(blocked==null){try{tokens=decode(vault.open(r.getString(3),proposalId),Tokens.class);}catch(IllegalArgumentException unavailable){blocked="KEY_BLOCKED";}}
                if(blocked!=null){if(restricted)transition(c,proposalId,blocked,null,null);else update(c,"UPDATE paper_approval_delivery SET state=? WHERE proposal_id=?",blocked,proposalId);c.commit();return blocked;}
            }
            if(restricted)transition(c,proposalId,"SENDING",attempt,null);
            else update(c,"UPDATE paper_approval_delivery SET state='SENDING',attempt_id=?,attempted_at=? WHERE proposal_id=?",attempt,Timestamp.from(clock.instant()),proposalId);
            c.commit(); // Never send before this durable claim. Uncertain commit => no send here.
        }catch(Exception failure){c.rollback();throw failure;}}
        String message=null;
        try{message=sender.send(proposal,tokens);if(message==null||!message.matches("[1-9][0-9]{0,18}"))message=null;}
        catch(InterruptedException interrupted){Thread.currentThread().interrupt();}
        catch(Exception uncertain){/* Do not retain provider exceptions, URLs, credentials or callback tokens. */}
        try(var c=connections.open()){begin(c);try{
            String state=message==null?"UNCERTAIN":"SENT";
            if(restricted)transition(c,proposalId,state,attempt,message);
            else if(update(c,"UPDATE paper_approval_delivery SET state=?,message_id=? WHERE proposal_id=? AND state='SENDING' AND attempt_id=?",state,message,proposalId,attempt)!=1)throw new IllegalStateException("Delivery acknowledgement conflict");
            c.commit();return state;
        }catch(Exception failure){c.rollback();throw failure;}}
    }
    private void transition(Connection c,String id,String state,String attempt,String message)throws SQLException {
        try(var s=statement(c,"SELECT paper_publish_transition(?,?,?,?,?)",id,state,attempt,Timestamp.from(clock.instant()),message);var r=s.executeQuery()){
            if(!r.next()||!r.getBoolean(1))throw new SQLException("Delivery transition refused");
        }
    }
    /** SENDING after a crash is deliberately not retried. It requires operational reconciliation. */
    static final class Vault {
        private final SecretKeySpec key;private final SecureRandom random=new SecureRandom();
        Vault(byte[] key){if(key==null||key.length!=32)throw new IllegalArgumentException("Explicit 256-bit delivery key required");this.key=new SecretKeySpec(key.clone(),"AES");}
        String seal(String plaintext,String id){try{byte[] iv=new byte[12];random.nextBytes(iv);Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key,new GCMParameterSpec(128,iv));cipher.updateAAD(id.getBytes(StandardCharsets.UTF_8));byte[] encrypted=cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));byte[] result=Arrays.copyOf(iv,iv.length+encrypted.length);System.arraycopy(encrypted,0,result,iv.length,encrypted.length);return Base64.getEncoder().encodeToString(result);}catch(Exception e){throw new IllegalArgumentException("Cannot seal delivery");}}
        String open(String sealed,String id){try{byte[] all=Base64.getDecoder().decode(sealed);if(all.length<28||all.length>3072)throw new IllegalArgumentException();Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key,new GCMParameterSpec(128,all,0,12));cipher.updateAAD(id.getBytes(StandardCharsets.UTF_8));return new String(cipher.doFinal(all,12,all.length-12),StandardCharsets.UTF_8);}catch(Exception e){throw new IllegalArgumentException("Delivery key or integrity unavailable");}}
    }
}
