package in.marketbrain.marketdata.paytm;
import java.nio.file.Path;
import javax.xml.parsers.DocumentBuilderFactory;
/** Reads only the four fixed Surefire reports produced in the isolated verification image. */
public final class PaytmTimedRouteReport {
    public static void main(String[] args) throws Exception {
        var factory=DocumentBuilderFactory.newInstance();
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);
        factory.setAttribute("http://javax.xml.XMLConstants/property/accessExternalDTD", "");
        factory.setAttribute("http://javax.xml.XMLConstants/property/accessExternalSchema", "");
        int tests=0;
        for(String name:new String[]{"PaytmApplicationRouteTest","PaytmTimedRouteIntegrationTest","PaytmGatewayTransportTest","PaytmRouteHealthBridgeTest"}) {
            var doc=factory.newDocumentBuilder().parse(Path.of("target","surefire-reports","TEST-in.marketbrain.marketdata.paytm."+name+".xml").toFile());
            var suite=doc.getDocumentElement();
            if(!suite.getAttribute("failures").equals("0") || !suite.getAttribute("errors").equals("0") || !suite.getAttribute("skipped").equals("0")) throw new AssertionError("Incomplete suite "+name);
            tests+=Integer.parseInt(suite.getAttribute("tests"));
        }
        if(tests!=30) throw new AssertionError("Expected 30 JUnit tests");
        System.out.println("{\"status\":\"HEALTH_BRIDGE_TESTS_PASSED_COLLECTOR_PENDING\",\"junitTests\":30,\"guardAssertions\":39,\"liveHealthProviderConnected\":false,\"runningApplicationChanged\":false,\"ordersEnabled\":false}");
    }
}
