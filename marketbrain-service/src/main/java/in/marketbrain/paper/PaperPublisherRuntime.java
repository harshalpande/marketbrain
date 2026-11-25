package in.marketbrain.paper;

import in.marketbrain.marketdata.paytm.PaytmPaperReviewAdapter;
import java.util.Arrays;

/** Explicit internal factory. Startup never connects, issues proposals or sends messages. */
public final class PaperPublisherRuntime implements AutoCloseable {
    private final PaperRuntimeCredential credential = new PaperRuntimeCredential();
    private final PaperWriterConnector.Target target;
    private final PaytmPaperReviewAdapter quotes;
    private final PaperApprovalDelivery.Sender sender;
    private final String keyFile;
    public PaperPublisherRuntime(PaperWriterConnector.Target target, PaytmPaperReviewAdapter quotes,
            PaperApprovalDelivery.Sender sender, String keyFile) {
        this.target=java.util.Objects.requireNonNull(target);this.quotes=java.util.Objects.requireNonNull(quotes);
        this.sender=java.util.Objects.requireNonNull(sender);this.keyFile=java.util.Objects.requireNonNull(keyFile);
    }
    PaperRuntimeCredential credential(){return credential;}
    public boolean ready(){return credential.ready();}
    public PaperPaytmReviewPublisher open() throws Exception {
        if(!credential.ready())throw new PaperRuntimeCredential.Locked();
        byte[] key=null;
        try {
            key=PaperApprovalStorage.readKey(keyFile);
            return PaperPaytmReviewPublisher.create(PaperWriterConnector.publisher(target,credential,true),quotes,sender,key);
        } finally {if(key!=null)Arrays.fill(key,(byte)0);}
    }
    @Override public void close(){credential.close();}
}
