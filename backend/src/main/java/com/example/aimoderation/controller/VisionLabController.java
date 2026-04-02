package com.example.aimoderation.controller;

import com.example.aimoderation.model.ImageModerationResult;
import com.example.aimoderation.model.ImageModerationStatus;
import com.example.aimoderation.model.User;
import com.example.aimoderation.repository.ImageModerationRepository;
import com.example.aimoderation.repository.UserRepository;
import com.example.aimoderation.service.ImageModerationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/vision-lab")
@CrossOrigin(origins = "*")
public class VisionLabController {

    private static final Logger logger = LoggerFactory.getLogger(VisionLabController.class);

    @Autowired
    private ImageModerationService imageModerationService;

    @Autowired
    private ImageModerationRepository imageModerationRepository;

    @Autowired
    private UserRepository userRepository;

    @Value("${moderation.image.max-size:10485760}")
    private long maxImageSize;

    @GetMapping({"", "/"})
    public ResponseEntity<?> getVisionLab(
            @RequestHeader(value = "Accept", required = false) String acceptHeader,
            @RequestParam(value = "format", required = false) String format) {
        if ("html".equalsIgnoreCase(format) || acceptsHtml(acceptHeader)) {
            return ResponseEntity.ok()
                    .contentType(MediaType.TEXT_HTML)
                    .body(buildVisionLabPage());
        }

        return ResponseEntity.ok(buildVisionLabInfo());
    }

    @PostMapping(value = {"", "/"}, consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<?> analyzeImageMultipart(
            @RequestParam("file") MultipartFile file,
            Authentication authentication) {
        try {
            ImageModerationResult result = imageModerationService.moderateImage(file, resolveUser(authentication));

            if (result.getStatus() == ImageModerationStatus.ERROR) {
                return ResponseEntity.badRequest().body(buildAnalysisResponse(result));
            }

            return ResponseEntity.ok(buildAnalysisResponse(result));
        } catch (Exception e) {
            logger.error("Vision lab multipart analysis failed: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "error", "Vision lab analysis failed.",
                    "message", e.getMessage()
            ));
        }
    }

    private Map<String, Object> buildVisionLabInfo() {
        Map<String, Object> response = new HashMap<>();
        response.put("title", "Vision Lab");
        response.put("engine", "Spatial Grid Ensemble");
        response.put("description", "Browser-safe image analysis using JSON uploads and the existing moderation algorithm.");
        response.put("methods", List.of("GET", "POST"));
        response.put("endpoint", "/api/vision-lab");
        response.put("acceptedTypes", List.of("image/jpeg", "image/png", "image/gif", "image/webp"));
        response.put("maxSizeBytes", maxImageSize);
        response.put("maxSizeLabel", formatMaxSize(maxImageSize));
        response.put("transport", List.of("application/json", "multipart/form-data"));
        response.put("field", "imageBase64");
        response.put("statusCounts", imageModerationService.getStats());
        response.put("totalAnalyses", imageModerationRepository.count());
        return response;
    }

    @GetMapping({"/{id:\\d+}", "/{id:\\d+}/"})
    public ResponseEntity<?> getVisionLabResult(@PathVariable Long id) {
        return imageModerationRepository.findById(id)
                .<ResponseEntity<?>>map(result -> ResponseEntity.ok(buildAnalysisResponse(result)))
                .orElse(ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of(
                        "error", "Analysis not found"
                )));
    }

    @PostMapping(value = {"", "/"}, consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> analyzeImage(
            @RequestBody VisionLabRequest request,
            Authentication authentication) {
        try {
            if (request == null || request.imageBase64() == null || request.imageBase64().isBlank()) {
                return ResponseEntity.badRequest().body(Map.of(
                        "error", "No image provided.",
                        "message", "Send JSON with filename, contentType, and imageBase64."
                ));
            }

            byte[] imageBytes = decodeBase64Image(request.imageBase64());
            User user = resolveUser(authentication);
            ImageModerationResult result = imageModerationService.moderateImage(
                    imageBytes,
                    sanitizeFilename(request.filename()),
                    request.contentType(),
                    user
            );

            if (result.getStatus() == ImageModerationStatus.ERROR) {
                return ResponseEntity.badRequest().body(buildAnalysisResponse(result));
            }

            return ResponseEntity.ok(buildAnalysisResponse(result));
        } catch (IllegalArgumentException e) {
            logger.warn("Invalid vision lab payload: {}", e.getMessage());
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Invalid image payload.",
                    "message", "Image data must be valid base64."
            ));
        } catch (Exception e) {
            logger.error("Vision lab analysis failed: {}", e.getMessage(), e);
            return ResponseEntity.internalServerError().body(Map.of(
                    "error", "Vision lab analysis failed.",
                    "message", e.getMessage()
            ));
        }
    }

    private User resolveUser(Authentication authentication) {
        if (authentication == null || authentication.getName() == null
                || "anonymousUser".equals(authentication.getName())) {
            return null;
        }
        return userRepository.findByUsername(authentication.getName()).orElse(null);
    }

    private Map<String, Object> buildAnalysisResponse(ImageModerationResult result) {
        Map<String, Object> response = new HashMap<>();
        response.put("analysisId", result.getId());
        response.put("filename", result.getImageUrl());
        response.put("status", result.getStatus().name());
        response.put("confidence", result.getConfidenceScore() != null ? result.getConfidenceScore() : 0.0);
        response.put("categories", parseCategories(result.getDetectedCategories()));
        response.put("reason", result.getModerationReason() != null ? result.getModerationReason() : "");
        response.put("createdAt", result.getCreatedAt());
        response.put("moderatedAt", result.getModeratedAt());
        response.put("engine", "Spatial Grid Ensemble");
        return response;
    }

    private List<String> parseCategories(String rawCategories) {
        if (rawCategories == null || rawCategories.isBlank()) {
            return List.of();
        }

        List<String> categories = new ArrayList<>();
        for (String category : rawCategories.split(",")) {
            String trimmed = category.trim();
            if (!trimmed.isEmpty()) {
                categories.add(trimmed);
            }
        }
        return categories;
    }

    private byte[] decodeBase64Image(String rawImage) {
        String normalized = rawImage.trim();
        int dataSeparator = normalized.indexOf(',');
        if (normalized.startsWith("data:") && dataSeparator >= 0) {
            normalized = normalized.substring(dataSeparator + 1);
        }
        return Base64.getDecoder().decode(normalized);
    }

    private String sanitizeFilename(String filename) {
        if (filename == null || filename.isBlank()) {
            return "vision-upload";
        }
        return filename.trim();
    }

    private String formatMaxSize(long bytes) {
        double megabytes = bytes / (1024.0 * 1024.0);
        return String.format("%.0f MB", megabytes);
    }

    private boolean acceptsHtml(String acceptHeader) {
        return acceptHeader != null && acceptHeader.contains(MediaType.TEXT_HTML_VALUE);
    }

    private String buildVisionLabPage() {
        String endpoint = "/api/vision-lab";
        String maxSize = formatMaxSize(maxImageSize);

        return """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <title>Vision Lab</title>
                  <style>
                    :root {
                      --bg: #130f0f;
                      --panel: rgba(33, 27, 27, 0.92);
                      --panel-2: rgba(24, 19, 19, 0.82);
                      --line: rgba(255, 255, 255, 0.09);
                      --text: #f4efe9;
                      --muted: #baafa3;
                      --accent: #ff7a59;
                      --accent-2: #ffb347;
                      --good: #78d37f;
                      --warn: #ffb347;
                      --bad: #ff7070;
                      --shadow: 0 24px 80px rgba(0, 0, 0, 0.45);
                      --radius: 24px;
                    }
                    * { box-sizing: border-box; }
                    body {
                      margin: 0;
                      min-height: 100vh;
                      font-family: "Segoe UI", sans-serif;
                      color: var(--text);
                      background:
                        radial-gradient(circle at top left, rgba(255,122,89,0.22), transparent 32%),
                        radial-gradient(circle at bottom right, rgba(255,179,71,0.18), transparent 28%),
                        linear-gradient(135deg, #110d0d, #171212 48%, #0d0b0b 100%);
                    }
                    .shell {
                      max-width: 1180px;
                      margin: 0 auto;
                      padding: 32px 20px 48px;
                    }
                    .hero {
                      display: grid;
                      grid-template-columns: 1.1fr 0.9fr;
                      gap: 18px;
                    }
                    .card {
                      background: var(--panel);
                      border: 1px solid var(--line);
                      border-radius: var(--radius);
                      box-shadow: var(--shadow);
                      overflow: hidden;
                    }
                    .card-inner { padding: 26px; }
                    .eyebrow {
                      display: inline-flex;
                      align-items: center;
                      gap: 8px;
                      padding: 8px 12px;
                      border-radius: 999px;
                      background: rgba(255,179,71,0.08);
                      border: 1px solid rgba(255,179,71,0.18);
                      color: #ffd29c;
                      font-size: 12px;
                      font-weight: 700;
                      letter-spacing: 0.12em;
                      text-transform: uppercase;
                    }
                    h1 {
                      margin: 18px 0 12px;
                      font-family: Georgia, serif;
                      font-size: clamp(38px, 7vw, 64px);
                      line-height: 0.98;
                      letter-spacing: -0.04em;
                    }
                    p {
                      margin: 0;
                      color: var(--muted);
                      line-height: 1.65;
                      font-size: 15px;
                    }
                    .meta-grid {
                      display: grid;
                      grid-template-columns: repeat(2, minmax(0, 1fr));
                      gap: 12px;
                      margin-top: 22px;
                    }
                    .meta-item {
                      padding: 14px 16px;
                      border-radius: 18px;
                      background: var(--panel-2);
                      border: 1px solid var(--line);
                    }
                    .meta-item strong {
                      display: block;
                      margin-bottom: 6px;
                      font-size: 12px;
                      color: #f9d4b6;
                      text-transform: uppercase;
                      letter-spacing: 0.08em;
                    }
                    .dropzone {
                      position: relative;
                      padding: 22px;
                      border-radius: 22px;
                      border: 1px dashed rgba(255,179,71,0.28);
                      background: linear-gradient(180deg, rgba(255,255,255,0.03), rgba(255,255,255,0.01));
                    }
                    .dropzone input {
                      width: 100%;
                      color: var(--text);
                    }
                    .actions {
                      display: flex;
                      gap: 12px;
                      margin-top: 16px;
                    }
                    button {
                      appearance: none;
                      border: 0;
                      border-radius: 16px;
                      padding: 14px 18px;
                      font-weight: 700;
                      cursor: pointer;
                      transition: transform 160ms ease, opacity 160ms ease;
                    }
                    button:hover { transform: translateY(-1px); }
                    button:disabled { opacity: 0.5; cursor: not-allowed; transform: none; }
                    .primary {
                      color: white;
                      background: linear-gradient(135deg, var(--accent), #ff946c);
                    }
                    .secondary {
                      color: var(--text);
                      background: rgba(255,255,255,0.06);
                      border: 1px solid var(--line);
                    }
                    .status-strip {
                      display: flex;
                      flex-wrap: wrap;
                      gap: 10px;
                      margin-top: 18px;
                    }
                    .pill {
                      padding: 10px 12px;
                      border-radius: 999px;
                      background: rgba(255,255,255,0.05);
                      border: 1px solid var(--line);
                      font-size: 12px;
                      color: var(--muted);
                    }
                    .result {
                      margin-top: 18px;
                      padding: 18px;
                      border-radius: 20px;
                      background: rgba(0,0,0,0.18);
                      border: 1px solid var(--line);
                    }
                    .result h2 {
                      margin: 0 0 12px;
                      font-size: 22px;
                      font-family: Georgia, serif;
                    }
                    .result-grid {
                      display: grid;
                      grid-template-columns: repeat(3, minmax(0, 1fr));
                      gap: 10px;
                      margin-top: 12px;
                    }
                    .result-grid div {
                      padding: 12px;
                      border-radius: 14px;
                      background: rgba(255,255,255,0.04);
                      border: 1px solid var(--line);
                    }
                    .label {
                      display: block;
                      margin-bottom: 5px;
                      font-size: 11px;
                      color: var(--muted);
                      text-transform: uppercase;
                      letter-spacing: 0.08em;
                    }
                    .value { font-size: 14px; color: var(--text); }
                    .good { color: var(--good); }
                    .warn { color: var(--warn); }
                    .bad { color: var(--bad); }
                    pre {
                      margin: 14px 0 0;
                      padding: 14px;
                      border-radius: 16px;
                      background: rgba(0,0,0,0.28);
                      border: 1px solid var(--line);
                      color: #e8ddd1;
                      white-space: pre-wrap;
                      word-break: break-word;
                    }
                    .hint {
                      margin-top: 14px;
                      font-size: 12px;
                      color: var(--muted);
                    }
                    @media (max-width: 900px) {
                      .hero { grid-template-columns: 1fr; }
                      .result-grid { grid-template-columns: 1fr; }
                      .actions { flex-direction: column; }
                    }
                  </style>
                </head>
                <body>
                  <div class="shell">
                    <div class="hero">
                      <section class="card">
                        <div class="card-inner">
                          <div class="eyebrow">Vision Lab / Browser Upload</div>
                          <h1>Upload a web image directly to the moderation engine.</h1>
                          <p>
                            This page is the backend-side UI for the new Vision Lab endpoint. GET opens the lab.
                            POST analyzes an image. The local AI algorithm stays the same, but the upload path is rebuilt for the browser.
                          </p>
                          <div class="meta-grid">
                            <div class="meta-item"><strong>Endpoint</strong><span>__ENDPOINT__</span></div>
                            <div class="meta-item"><strong>Methods</strong><span>GET and POST</span></div>
                            <div class="meta-item"><strong>Payload</strong><span>JSON or multipart form</span></div>
                            <div class="meta-item"><strong>Max Size</strong><span>__MAX_SIZE__</span></div>
                          </div>
                        </div>
                      </section>
                      <section class="card">
                        <div class="card-inner">
                          <div class="dropzone">
                            <input id="fileInput" type="file" accept="image/jpeg,image/png,image/gif,image/webp">
                            <div class="status-strip">
                              <div class="pill" id="fileStatus">No image selected</div>
                              <div class="pill">JPEG / PNG / GIF / WebP</div>
                              <div class="pill">__MAX_SIZE__ max</div>
                            </div>
                            <div class="actions">
                              <button class="primary" id="analyzeButton">Run Vision Lab</button>
                              <button class="secondary" id="refreshButton" type="button">Refresh Stats</button>
                            </div>
                            <div class="hint">This page posts multipart form data to the same endpoint, so it works directly in the browser without the frontend app.</div>
                          </div>
                          <div class="result" id="resultCard">
                            <h2>Waiting for analysis</h2>
                            <p>Choose an image, then run the lab. Results and status counts will appear here.</p>
                            <pre id="resultJson">No result yet.</pre>
                          </div>
                        </div>
                      </section>
                    </div>
                  </div>
                  <script>
                    const endpoint = '__ENDPOINT__';
                    const fileInput = document.getElementById('fileInput');
                    const fileStatus = document.getElementById('fileStatus');
                    const resultCard = document.getElementById('resultCard');
                    const resultJson = document.getElementById('resultJson');
                    const analyzeButton = document.getElementById('analyzeButton');
                    const refreshButton = document.getElementById('refreshButton');

                    function statusClass(status) {
                      if (status === 'SAFE') return 'good';
                      if (status === 'REJECTED') return 'bad';
                      return 'warn';
                    }

                    function setResult(title, body, raw, status) {
                      resultCard.innerHTML = `
                        <h2>${title}</h2>
                        <div class="result-grid">
                          <div><span class="label">Status</span><span class="value ${statusClass(status)}">${status || 'N/A'}</span></div>
                          <div><span class="label">Reason</span><span class="value">${body.reason || body.message || '-'}</span></div>
                          <div><span class="label">Categories</span><span class="value">${(body.categories || []).join(', ') || 'None'}</span></div>
                        </div>
                        <pre id="resultJson"></pre>
                      `;
                      document.getElementById('resultJson').textContent = JSON.stringify(raw, null, 2);
                    }

                    async function refreshInfo() {
                      const response = await fetch(endpoint + '?format=json', {
                        headers: { 'Accept': 'application/json' }
                      });
                      const body = await response.json();
                      if (!response.ok) {
                        setResult('Vision Lab Error', body, body, 'ERROR');
                        return;
                      }
                      setResult('Vision Lab Ready', {
                        reason: 'Engine: ' + body.engine + ' | Total analyses: ' + body.totalAnalyses,
                        categories: Object.entries(body.statusCounts || {})
                          .map(([key, value]) => `${key}:${value}`)
                      }, body, 'SAFE');
                    }

                    fileInput.addEventListener('change', () => {
                      const file = fileInput.files[0];
                      fileStatus.textContent = file
                        ? `${file.name} (${(file.size / 1024).toFixed(1)} KB)`
                        : 'No image selected';
                    });

                    analyzeButton.addEventListener('click', async () => {
                      const file = fileInput.files[0];
                      if (!file) {
                        setResult('No file selected', { message: 'Choose an image before running the lab.' }, { error: 'No file selected' }, 'ERROR');
                        return;
                      }

                      const formData = new FormData();
                      formData.append('file', file);

                      analyzeButton.disabled = true;
                      analyzeButton.textContent = 'Analyzing...';
                      try {
                        const response = await fetch(endpoint, { method: 'POST', body: formData });
                        const body = await response.json();
                        setResult('Vision Lab Result', body, body, body.status || 'ERROR');
                      } catch (error) {
                        setResult('Request failed', { message: error.message }, { error: error.message }, 'ERROR');
                      } finally {
                        analyzeButton.disabled = false;
                        analyzeButton.textContent = 'Run Vision Lab';
                      }
                    });

                    refreshButton.addEventListener('click', refreshInfo);
                    refreshInfo();
                  </script>
                </body>
                </html>
                """
                .replace("__ENDPOINT__", endpoint)
                .replace("__MAX_SIZE__", maxSize);
    }

    private record VisionLabRequest(String filename, String contentType, String imageBase64) {}
}
