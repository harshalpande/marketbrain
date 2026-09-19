package in.marketbrain.training;

import org.junit.jupiter.api.Test;
import java.io.File;
import static org.assertj.core.api.Assertions.*;
import static in.marketbrain.training.NumericalResearchExportTest.MAPPER;

/** Explicit saved-data replay only; excluded from standard test discovery. */
class NumericalResearchMappingEvidenceProbe {
    @Test void mapSavedExpandedInputWithoutRuntimeDependencies() throws Exception {
        var saved=MAPPER.readTree(new File(System.getProperty("researchEvidence")));
        var input=MAPPER.treeToValue(saved.get("request"),NumericalResearchExport.Input.class);
        var result=new NumericalResearchMapping().build(input);
        assertThat(result.rowCount()).isEqualTo(600);assertThat(result.mappingReadyCount()).isEqualTo(600);
        assertThat(result.trainingEligibleCount()).isZero();assertThat(result.dateCoverage()).hasSize(150);
        MAPPER.writeValue(new File("target/research-mapping-replay.json"),result);
        System.out.println("Saved evidence: 600 mapped rows, 150 date groups, zero training-eligible rows.");
    }
}
