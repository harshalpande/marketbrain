package in.marketbrain.training;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.util.concurrent.Semaphore;

@RestController
@RequestMapping("/api/v1/training")
public class NumericalResearchExportController {
    private static final int MAX_BYTES=2*1024*1024;
    private final ObjectMapper mapper;
    private final Semaphore slot=new Semaphore(1);
    public NumericalResearchExportController(ObjectMapper mapper){this.mapper=mapper;}
    @PostMapping(value="/numerical-research-export",consumes="application/json")
    public NumericalResearchExport.Result export(HttpServletRequest request) throws IOException {
        return export(request,false);
    }
    @PostMapping(value="/numerical-expanded-research-export",consumes="application/json")
    public NumericalResearchExport.Result exportExpanded(HttpServletRequest request) throws IOException {
        return export(request,true);
    }
    @PostMapping(value="/numerical-research-mapping",consumes="application/json")
    public NumericalResearchMapping.Result mapping(HttpServletRequest request) throws IOException {
        if(!slot.tryAcquire())throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Research preparation already running; no queue.");
        try {
            byte[] bytes=request.getInputStream().readNBytes(MAX_BYTES+1);
            if(bytes.length>MAX_BYTES)throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE);
            return new NumericalResearchMapping().build(mapper.readValue(bytes,NumericalResearchExport.Input.class));
        } catch(com.fasterxml.jackson.core.JsonProcessingException|IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid bounded saved-evidence input.");
        } finally {slot.release();}
    }
    private NumericalResearchExport.Result export(HttpServletRequest request,boolean expanded) throws IOException {
        if(!slot.tryAcquire())throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Export already running; no queue.");
        try {
            // Bound bytes even when Content-Length is absent or inaccurate. No DB work or server persistence.
            byte[] bytes=request.getInputStream().readNBytes(MAX_BYTES+1);
            if(bytes.length>MAX_BYTES)throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE);
            var input=mapper.readValue(bytes,NumericalResearchExport.Input.class);
            var builder=new NumericalResearchExport();
            return expanded?builder.buildExpanded(input):builder.build(input);
        } catch(com.fasterxml.jackson.core.JsonProcessingException|IllegalArgumentException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Invalid bounded saved-evidence input.");
        } finally {slot.release();}
    }
}
