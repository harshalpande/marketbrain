package in.marketbrain.marketdata.paytm;
import java.util.concurrent.atomic.AtomicLong;
public final class PaytmDiagnosticTimingVerification {
    private static int checks;
    private static void check(boolean ok, String name) { if (!ok) throw new AssertionError(name); checks++; }
    private static final class Fixture {
        final AtomicLong nano = new AtomicLong(), wall = new AtomicLong();
        final PaytmDiagnosticTimingGuard guard = new PaytmDiagnosticTimingGuard(nano::get, wall::get);
        long seq;
        boolean health(boolean sync, boolean route, double low, double high) {
            return guard.observe(new PaytmDiagnosticTimingGuard.Health(guard.bootId(), seq++, sync, route, low, high));
        }
        void advance(long millis) { nano.addAndGet(millis*1_000_000); wall.addAndGet(millis); }
    }
    public static void main(String[] args) {
        Fixture f = new Fixture();
        check(!f.guard.arm().diagnosticAllowed(), "missing evidence");
        check(f.health(true,true,-1,1), "healthy");
        check(!f.guard.checkAndConsume().diagnosticAllowed(), "observe never arms");
        check(f.guard.arm().diagnosticAllowed(), "explicit arm");
        for(int i=0;i<4;i++) check(f.guard.checkAndConsume().diagnosticAllowed(), "bounded call");
        check(!f.guard.checkAndConsume().diagnosticAllowed(), "budget exhausted");
        f.guard.arm(); f.guard.lock(); check(!f.guard.checkAndConsume().diagnosticAllowed(), "explicit lock");
        for(int type=0;type<7;type++) {
            f=new Fixture(); f.health(true,true,0,0);f.guard.arm();
            boolean accepted=switch(type) {
                case 0 -> f.health(false,true,0,0);
                case 1 -> f.health(true,false,0,0);
                case 2 -> f.health(true,true,Double.NaN,0);
                case 3 -> f.health(true,true,0,Double.POSITIVE_INFINITY);
                case 4 -> f.health(true,true,2,1);
                case 5 -> f.health(true,true,-5.001,0);
                default -> f.health(true,true,0,5.001);
            };
            check(!accepted && !f.guard.checkAndConsume().diagnosticAllowed(), "bad health latches");
            f.health(true,true,0,0);check(!f.guard.checkAndConsume().diagnosticAllowed(), "no automatic rearm");
        }
        for(long jump:new long[]{5001,-5001,Long.MIN_VALUE,Long.MAX_VALUE}) {
            f=new Fixture();f.health(true,true,0,0);f.guard.arm();f.wall.set(jump);
            check(!f.guard.checkAndConsume().diagnosticAllowed(), "wall jump blocked");
        }
        f=new Fixture();f.health(true,true,0,0);f.guard.arm();f.advance(29999);
        check(f.guard.checkAndConsume().diagnosticAllowed(),"health just before expiry");f.advance(1);
        check(!f.guard.checkAndConsume().diagnosticAllowed(),"health expires at boundary");
        f=new Fixture();f.health(true,true,0,0);f.guard.arm();
        for(int i=0;i<4;i++){f.advance(25000);f.health(true,true,0,0);}
        check(!f.guard.checkAndConsume().diagnosticAllowed(),"refresh does not extend lease");
        f=new Fixture();f.health(true,true,0,0);f.guard.arm();f.nano.set(-1);
        check(!f.guard.checkAndConsume().diagnosticAllowed(),"monotonic reset");
        f=new Fixture();f.health(true,true,0,0);f.guard.arm();
        check(!f.guard.observe(new PaytmDiagnosticTimingGuard.Health(f.guard.bootId(),0,true,true,0,0)),"replay");
        check(!f.guard.checkAndConsume().diagnosticAllowed(),"replay revokes");
        f=new Fixture();f.health(true,true,0,0);f.guard.arm();f.wall.set(6000);f.health(true,true,0,0);
        check(!f.guard.checkAndConsume().diagnosticAllowed(),"fresh evidence cannot mask jump and retain lease");
        Fixture fresh=new Fixture();
        check(!fresh.guard.bootId().equals(f.guard.bootId()),"new boot identity");
        check(!fresh.guard.observe(new PaytmDiagnosticTimingGuard.Health(f.guard.bootId(),9,true,true,0,0)),"old boot rejected");
        check(!fresh.guard.arm().diagnosticAllowed(),"restart locked");
        check(!fresh.guard.observe(null),"null evidence");
        System.out.println("{\"status\":\"TIMING_GUARD_ENGINEERING_PASSED_INTEGRATION_PENDING\",\"checks\":"+checks+",\"networkCalls\":0,\"ordersEnabled\":false,\"applicationWired\":false}");
    }
}
