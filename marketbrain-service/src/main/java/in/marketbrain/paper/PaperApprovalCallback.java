package in.marketbrain.paper;

import java.sql.SQLException;
import java.util.Objects;

/** Trusted long-poll adapter only. Registered only by explicit, default-off review configuration. */
public final class PaperApprovalCallback {
    private final PaperApprovalReview review;
    private final java.util.function.BooleanSupplier ready;
    public PaperApprovalCallback(PaperApprovalReview review){this(review,()->true);}
    public PaperApprovalCallback(PaperApprovalReview review,java.util.function.BooleanSupplier ready){
        this.review=Objects.requireNonNull(review);this.ready=Objects.requireNonNull(ready);
    }
    public String handle(String callbackId,long userId,long chatId,String chatType,String data)throws SQLException{
        if(!"private".equals(chatType)||data==null||!data.matches("mbp:[A-Za-z0-9_-]{43}"))throw new IllegalArgumentException("Invalid private approval action");
        if(!ready.getAsBoolean())throw new PaperRuntimeCredential.Locked();
        var receipt=review.process(new PaperApprovalReview.Callback(callbackId,userId,chatId,true,data.substring(4)));
        return switch(receipt.status()){
            case "ACCEPTED_EXECUTION_BLOCKED"->"PAPER review accepted. Execution remains disabled; no order or reservation created.";
            case "REJECTED"->"PAPER proposal rejected. No trade created.";
            case "EXPIRED"->"PAPER proposal expired. No trade created.";
            default->"PAPER review blocked: "+receipt.status()+". No trade created.";
        };
    }
}
