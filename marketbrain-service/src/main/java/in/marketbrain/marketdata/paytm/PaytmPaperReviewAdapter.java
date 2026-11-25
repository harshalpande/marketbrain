package in.marketbrain.marketdata.paytm;

import in.marketbrain.paper.PaperApprovalReview;
import in.marketbrain.paper.PaperReviewTestPolicy;
import org.springframework.jdbc.core.JdbcTemplate;
import java.math.BigDecimal;
import java.time.*;
import java.util.*;

/** Internal opt-in bridge only. No Spring bean, proposal issuer, HTTP endpoint, callback or order activation. */
public final class PaytmPaperReviewAdapter implements PaperApprovalReview.QuoteSource, AutoCloseable {
    private final PaytmSupervisedController session;
    private final PaytmUniverseMatch universe;
    private final PaytmReviewIdentity identity;
    private final Clock clock;
    public static PaytmPaperReviewAdapter create(PaytmSupervisedController session, JdbcTemplate applicationReadJdbc) {
        return new PaytmPaperReviewAdapter(session,new PaytmUniverseMatch(applicationReadJdbc),new PaytmReviewIdentity());
    }
    PaytmPaperReviewAdapter(PaytmSupervisedController session,PaytmUniverseMatch universe,PaytmReviewIdentity identity) {
        this.session=Objects.requireNonNull(session);this.universe=Objects.requireNonNull(universe);this.identity=Objects.requireNonNull(identity);
        this.clock=new Clock(){
            public ZoneId getZone(){return ZoneOffset.UTC;}
            public Clock withZone(ZoneId zone){if(!ZoneOffset.UTC.equals(zone))throw new IllegalArgumentException("UTC review clock required");return this;}
            public Instant instant(){return session.reviewInstant();}
        };
    }
    public Clock clock(){return clock;}
    @Override public PaperApprovalReview.MarketQuote latest(PaperApprovalReview.Proposal proposal) {
        try {
            var policy=PaperReviewTestPolicy.paytmPolicy();
            Instant before=clock.instant();
            if(!proposal.policyId().equals(policy.id())||before.isBefore(proposal.terms().createdAt())||!before.isBefore(proposal.terms().expiresAt())
                    ||Duration.between(proposal.terms().createdAt(),proposal.terms().expiresAt()).compareTo(policy.maxProposalLifetime())>0)
                throw new IllegalArgumentException();
            // Resolve again at callback time; never reuse the previously captured quote or caller security ID.
            var bound=identity.resolve(proposal.terms().symbol(),universe.inspect(proposal.terms().symbol()));
            Map<String,Object> evidence=bound.evidence();
            if(number(evidence.get("instrumentId"))!=proposal.instrumentId()||!proposal.terms().symbol().equals(evidence.get("symbol")))throw new IllegalArgumentException();
            Map<String,Object> quote=session.readBoundQuote(bound.securityId());
            Instant now=clock.instant();
            if(!now.isBefore(proposal.terms().expiresAt())||!Boolean.TRUE.equals(quote.get("fresh"))||!Boolean.FALSE.equals(quote.get("ordersEnabled"))
                    ||!"FRESH_QUOTE_OBSERVED".equals(quote.get("status"))||number(quote.get("securityId"))!=bound.securityId()
                    ||!"NSE".equals(quote.get("exchange"))||!"EQUITY".equals(quote.get("scripType"))||!"PAYTM_1980_SECONDS".equals(quote.get("timestampEpoch")))throw new IllegalArgumentException();
            Instant traded=Instant.ofEpochMilli(number(quote.get("tradeEpochMilliseconds"))),received=Instant.ofEpochMilli(number(quote.get("observedEpochMilliseconds")));
            if(traded.isBefore(proposal.terms().createdAt())||traded.isAfter(received)||received.isBefore(before)||received.isAfter(now)
                    ||Duration.between(traded,now).toMillis()>policy.limits().maxQuoteAgeMillis()
                    ||number(quote.get("ageMilliseconds"))!=Duration.between(traded,received).toMillis())throw new IllegalArgumentException();
            if(!(quote.get("lastPrice") instanceof Number value))throw new IllegalArgumentException();
            long paise=new BigDecimal(value.toString()).movePointRight(2).longValueExact();
            if(paise<=0)throw new IllegalArgumentException();
            return new PaperApprovalReview.MarketQuote(proposal.instrumentId(),proposal.terms().symbol(),"PAYTM",paise,traded,received);
        }catch(RuntimeException unavailable){
            // Provider/file contents, credentials and underlying exception details never enter Telegram receipts.
            throw new IllegalStateException("PAYTM_REVIEW_QUOTE_UNAVAILABLE");
        }
    }
    private static long number(Object value){if(!(value instanceof Number n))throw new IllegalArgumentException();return new BigDecimal(n.toString()).longValueExact();}
    @Override public void close(){identity.close();}
}
