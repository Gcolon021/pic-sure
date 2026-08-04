package edu.harvard.dbmi.avillach.dictionary.legacysearch;

import edu.harvard.dbmi.avillach.contracts.query.v3.SearchRequest;
import edu.harvard.dbmi.avillach.dictionary.AuditAttributes;
import edu.harvard.dbmi.avillach.dictionary.legacysearch.model.LegacyResponse;
import edu.harvard.dbmi.avillach.logging.AuditEvent;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;

@RestController
public class LegacySearchController {

    private final LegacySearchService legacySearchService;

    @Autowired
    private HttpServletRequest httpRequest;

    @Autowired
    public LegacySearchController(LegacySearchService legacySearchService) {
        this.legacySearchService = legacySearchService;
    }

    // Dashboard-safe parity with the deployed stream: keep this label until the migration in
    // docs/superpowers/specs/2026-08-04-audit-splunk-parity-design.md and
    // docs/superpowers/api_contract_followups/audit-label-accuracy.md is complete.
    @AuditEvent(type = "SEARCH", action = "search.legacy")
    @PostMapping(path = "/search")
    public ResponseEntity<LegacyResponse> legacySearch(
        @RequestBody SearchRequest request, @RequestParam(name = "page_number", defaultValue = "0", required = false) int page,
        @RequestParam(name = "page_size", defaultValue = "10", required = false) int size
    ) {
        AuditAttributes
            .putMetadata(httpRequest, "search_term", LegacySearchService.constructTsQuery(request.query() != null ? request.query() : ""));
        return ResponseEntity.ok(new LegacyResponse(legacySearchService.getSearchResults(request.query(), PageRequest.of(page, size))));
    }

}
