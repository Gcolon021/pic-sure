package edu.harvard.dbmi.avillach.dictionary.legacysearch;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import edu.harvard.dbmi.avillach.contracts.query.v3.SearchRequest;
import edu.harvard.dbmi.avillach.dictionary.AuditAttributes;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

class LegacySearchControllerAuditMetadataTest {

    private final LegacySearchService service = mock(LegacySearchService.class);
    private final MockHttpServletRequest request = new MockHttpServletRequest();
    private final LegacySearchController controller = new LegacySearchController(service);

    @BeforeEach
    void setUp() {
        when(service.getSearchResults(any(), any())).thenReturn(List.of());
        ReflectionTestUtils.setField(controller, "httpRequest", request);
    }

    @Test
    void emitsTheLegacyTsQueryAsSearchTermMetadata() {
        controller.legacySearch(new SearchRequest("tutorial-biolincc digitalis"), 0, 10);

        assertThat(AuditAttributes.getMetadata(request)).containsEntry("search_term", "tutorial:* & biolincc:* & digitalis:*");
    }

    @Test
    void emitsAnEmptySearchTermWhenTheQueryIsAbsent() {
        controller.legacySearch(new SearchRequest(null), 0, 10);

        assertThat(AuditAttributes.getMetadata(request)).containsEntry("search_term", "");
    }
}
