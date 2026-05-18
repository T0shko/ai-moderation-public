package com.example.aimoderation.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Validates Hugging Face API token and serverless inference connectivity.
 */
@Service
public class HuggingFaceIntegrationService {

    private static final Logger logger = LoggerFactory.getLogger(HuggingFaceIntegrationService.class);

    private static final String WHOAMI_URL = "https://huggingface.co/api/whoami-v2";
    private static final String INFERENCE_PROBE_MODEL = "Falconsai/nsfw_image_detection";
    private static final String INFERENCE_BASE =
            "https://router.huggingface.co/hf-inference/models/";

    @Value("${huggingface.api.token:}")
    private String hfApiToken;

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public Map<String, Object> getStatus() {
        Map<String, Object> status = new LinkedHashMap<>();
        boolean configured = hfApiToken != null && !hfApiToken.isBlank();
        status.put("configured", configured);
        status.put("cloudClipZeroShot", false);
        status.put("cloudNsfwModel", INFERENCE_PROBE_MODEL);

        if (!configured) {
            status.put("tokenValid", false);
            status.put("inferenceReachable", false);
            status.put("message",
                    "No token set. Add HUGGINGFACE_API_TOKEN to .env and restart the backend.");
            return status;
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setBearerAuth(hfApiToken.trim());
            ResponseEntity<String> whoami = restTemplate.exchange(
                    WHOAMI_URL, HttpMethod.GET, new HttpEntity<>(headers), String.class);

            if (!whoami.getStatusCode().is2xxSuccessful() || whoami.getBody() == null) {
                status.put("tokenValid", false);
                status.put("inferenceReachable", false);
                status.put("message", "Token rejected by Hugging Face (HTTP "
                        + whoami.getStatusCode().value() + ").");
                return status;
            }

            JsonNode profile = objectMapper.readTree(whoami.getBody());
            status.put("tokenValid", true);
            status.put("username", profile.path("name").asText("unknown"));

            boolean inferenceOk = probeInference(headers);
            status.put("inferenceReachable", inferenceOk);
            status.put("message", inferenceOk
                    ? "Token is valid and Inference API is reachable. "
                            + "Cloud layer uses " + INFERENCE_PROBE_MODEL
                            + " (Edge CLIP handles weapons/violence locally)."
                    : "Token is valid but Inference API probe failed. "
                            + "Check token permissions (Inference → serverless).");
            return status;
        } catch (Exception e) {
            logger.warn("Hugging Face status check failed: {}", e.getMessage());
            status.put("tokenValid", false);
            status.put("inferenceReachable", false);
            status.put("message", "Could not verify token: " + e.getMessage());
            return status;
        }
    }

    public boolean isTokenConfigured() {
        return hfApiToken != null && !hfApiToken.isBlank();
    }

    public boolean isInferenceReachable() {
        Map<String, Object> status = getStatus();
        return Boolean.TRUE.equals(status.get("tokenValid"))
                && Boolean.TRUE.equals(status.get("inferenceReachable"));
    }

    private boolean probeInference(HttpHeaders authHeaders) {
        byte[] jpeg = minimalJpeg();
        HttpHeaders headers = new HttpHeaders(authHeaders);
        headers.setContentType(MediaType.IMAGE_JPEG);
        headers.set("x-wait-for-model", "true");

        try {
            ResponseEntity<String> response = restTemplate.exchange(
                    INFERENCE_BASE + INFERENCE_PROBE_MODEL,
                    HttpMethod.POST,
                    new HttpEntity<>(jpeg, headers),
                    String.class);
            return response.getStatusCode().is2xxSuccessful()
                    && response.getBody() != null
                    && response.getBody().contains("label");
        } catch (Exception e) {
            logger.debug("HF inference probe failed: {}", e.getMessage());
            return false;
        }
    }

    /** Tiny valid JPEG for connectivity probes. */
    private static byte[] minimalJpeg() {
        return new byte[] {
            (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0x00, 0x10, 0x4A, 0x46,
            0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
            (byte) 0xFF, (byte) 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06,
            0x05, 0x08, 0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D,
            0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12, 0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F,
            0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C,
            0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34,
            0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32,
            (byte) 0xFF, (byte) 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01,
            0x01, 0x01, 0x11, 0x00, (byte) 0xFF, (byte) 0xC4, 0x00, 0x1F, 0x00,
            0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0A, 0x0B, (byte) 0xFF, (byte) 0xC4, 0x00, (byte) 0xB5,
            0x10, 0x00, 0x02, 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04,
            0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05,
            0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14,
            0x32, (byte) 0x81, (byte) 0x91, (byte) 0xA1, 0x08, 0x23, 0x42, (byte) 0xB1,
            (byte) 0xC1, 0x15, 0x52, (byte) 0xD1, (byte) 0xF0, 0x24, 0x33, 0x62, 0x72,
            (byte) 0xFF, (byte) 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
            (byte) 0xD2, (byte) 0xCF, 0x20, (byte) 0xFF, (byte) 0xD9
        };
    }
}
