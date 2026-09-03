package in.marketbrain.marketdata.backfill;

public enum QualityResolutionType {
    VERIFIED_EXCHANGE_MOVE(true, false),
    CORPORATE_ACTION_TRANSITION(true, true),
    PROVIDER_ADJUSTMENT(true, true),
    FEATURE_WINDOW_EXCLUDED(true, true),
    SECONDARY_SOURCE_BACKFILLED(true, false),
    PROVIDER_OMISSION_CONFIRMED(false, false);

    private final boolean allowsTraining;
    private final boolean requiresExclusion;

    QualityResolutionType(boolean allowsTraining, boolean requiresExclusion) {
        this.allowsTraining = allowsTraining;
        this.requiresExclusion = requiresExclusion;
    }

    public boolean allowsTraining() {
        return allowsTraining;
    }

    public boolean requiresExclusion() {
        return requiresExclusion;
    }
}
