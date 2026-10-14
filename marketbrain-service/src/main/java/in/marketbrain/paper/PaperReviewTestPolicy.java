package in.marketbrain.paper;

import java.time.Duration;

/** Owner-approved REVIEW ONLY contract. Never a fill/execution authority or default live-trading policy. */
public final class PaperReviewTestPolicy {
    public static final String ID = "PAPER_TELEGRAM_TEST_100S_V1";
    private PaperReviewTestPolicy() {}
    public static PaperApprovalReview.PolicyVersion policy() {
        // The last two fields bound synthetic evidence capacity; no order/fill adapter is registered.
        return new PaperApprovalReview.PolicyVersion(ID, "UPSTOX",
                new PaperAccountEngineering.Policy(15000, 50, 1, 500000, 2, 1), Duration.ofSeconds(100));
    }
    public static void requireExact(PaperApprovalReview.PolicyVersion policy) {
        if (!policy().equals(policy)) throw new IllegalArgumentException("Approved review-only policy required");
    }
}
