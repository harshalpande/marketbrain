package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.io.File;
import static org.assertj.core.api.Assertions.*;

/** Explicit offline replay of user-supplied saved evidence; not part of default test discovery. */
class NumericalExpandedResearchEvidenceProbe {
    @Test void replaySavedResearchWithoutServices() throws Exception {
        var mapper=NumericalResearchExportTest.MAPPER;
        var saved=mapper.readTree(new File(System.getProperty("researchEvidence")));
        var original=mapper.treeToValue(saved.get("request"),NumericalResearchExport.Input.class);
        var expanded=new NumericalResearchExport.Input(original.datasetRunId(),original.datasetManifestHash(),original.featureEvidenceSha256(),
                original.outcomeEvidenceSha256(),NumericalExpandedResearchTest.sessions(),original.instruments());
        var result=new NumericalResearchExport().buildExpanded(expanded);
        assertThat(result.candidateRowCount()).isEqualTo(600);assertThat(result.completeArithmeticRowCount()).isEqualTo(600);
        assertThat(result.blockedRowCount()).isZero();assertThat(result.certifiedLabelCount()).isZero();assertThat(result.trainingAuthorized()).isFalse();
        int rows=0,values=0;
        for(var old:saved.path("result").path("rows")){
            var generated=result.rows().stream().filter(r->r.instrumentId()==old.path("instrumentId").asLong()
                    &&r.decisionDate().toString().equals(old.path("decisionDate").asText())).findFirst().orElseThrow();
            com.fasterxml.jackson.databind.JsonNode features=mapper.valueToTree(generated.featureSnapshot().features());
            var expected=old.path("featureSnapshot").path("features");assertThat(features.size()).isEqualTo(expected.size());
            expected.fields().forEachRemaining(field->assertThat(features.get(field.getKey()).decimalValue()).isEqualByComparingTo(field.getValue().decimalValue()));
            assertThat(generated.outcome().indicativeGrossPercent()).isEqualByComparingTo(old.path("outcome").path("indicativeGrossPercent").decimalValue());
            rows++;values+=features.size();
        }
        assertThat(rows).isEqualTo(152);
        mapper.writeValue(new File("target/replayed-expanded-research-test-only.json"),result);
        System.out.println("EXPANDED SAVED EVIDENCE: 600/600 arithmetic rows; "+rows+" old rows and "+values+" feature values unchanged; training blocked.");
    }
}
