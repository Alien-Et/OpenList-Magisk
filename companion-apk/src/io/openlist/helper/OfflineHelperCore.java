package io.openlist.helper;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Pure Java standard library implementation for offline download helpers.
 * Contains zero Android dependencies so it can compile and run directly
 * in standard JVM unit tests as well as Android DEX.
 */
public final class OfflineHelperCore {

    private static final Pattern MAGNET_PATTERN = Pattern.compile("(?i)magnet:\\?[^\\s\"'<>]+");
    private static final Pattern HEX_HASH_PATTERN = Pattern.compile("(?i)\\b[0-9a-f]{40}\\b");
    private static final Pattern BASE32_HASH_PATTERN = Pattern.compile("(?i)\\b[a-z2-7]{32}\\b");

    private static final String SQLITE_STRING_TYPE_SUFFIX = "string";
    private static final int MIN_POLLUTED_TOKEN_LENGTH = 26;

    private OfflineHelperCore() {}

    private static class TextSpan {
        final int start;
        final int end;

        TextSpan(int start, int end) {
            this.start = start;
            this.end = end;
        }

        boolean contains(int s, int e) {
            return s >= start && e <= end;
        }
    }

    private static class MatchCandidate {
        final int startIndex;
        final String url;

        MatchCandidate(int startIndex, String url) {
            this.startIndex = startIndex;
            this.url = url;
        }
    }

    private static boolean isCoveredByMagnet(int start, int end, String hashLower, List<TextSpan> magnetSpans, List<String> magnetUrls) {
        for (TextSpan span : magnetSpans) {
            if (span.contains(start, end)) {
                return true;
            }
        }
        for (String m : magnetUrls) {
            if (m.toLowerCase(Locale.ROOT).contains(hashLower)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Extracts all magnet links and InfoHashes from rawText.
     * Standalone 40-char hex or 32-char base32 hashes are normalized to magnet:?xt=urn:btih:<hash>.
     * Preserves order of appearance and deduplicates.
     */
    public static List<String> extractMagnetUrls(String rawText) {
        if (rawText == null || rawText.trim().isEmpty()) {
            return Collections.emptyList();
        }

        List<MatchCandidate> candidates = new ArrayList<>();
        List<TextSpan> magnetSpans = new ArrayList<>();
        List<String> magnetUrls = new ArrayList<>();

        // 1. Extract standard magnet links
        Matcher magnetMatcher = MAGNET_PATTERN.matcher(rawText);
        while (magnetMatcher.find()) {
            String url = magnetMatcher.group();
            // Strip trailing sentence punctuation if accidentally captured
            while (url.endsWith(".") || url.endsWith(",") || url.endsWith(";")) {
                url = url.substring(0, url.length() - 1);
            }
            int start = magnetMatcher.start();
            int end = start + url.length();
            magnetSpans.add(new TextSpan(start, end));
            magnetUrls.add(url);
            candidates.add(new MatchCandidate(start, url));
        }

        // 2. Extract standalone 40-char hex hashes
        List<TextSpan> hexSpans = new ArrayList<>();
        Matcher hexMatcher = HEX_HASH_PATTERN.matcher(rawText);
        while (hexMatcher.find()) {
            int start = hexMatcher.start();
            int end = hexMatcher.end();
            String hash = hexMatcher.group();

            if (isCoveredByMagnet(start, end, hash.toLowerCase(Locale.ROOT), magnetSpans, magnetUrls)) {
                continue;
            }

            hexSpans.add(new TextSpan(start, end));
            candidates.add(new MatchCandidate(start, "magnet:?xt=urn:btih:" + hash));
        }

        // 3. Extract standalone 32-char base32 hashes
        Matcher b32Matcher = BASE32_HASH_PATTERN.matcher(rawText);
        while (b32Matcher.find()) {
            int start = b32Matcher.start();
            int end = b32Matcher.end();
            String hash = b32Matcher.group();

            if (isCoveredByMagnet(start, end, hash.toLowerCase(Locale.ROOT), magnetSpans, magnetUrls)) {
                continue;
            }

            // Skip if overlapping with an accepted hex span
            boolean withinHex = false;
            for (TextSpan span : hexSpans) {
                if (span.contains(start, end)) {
                    withinHex = true;
                    break;
                }
            }
            if (withinHex) continue;

            candidates.add(new MatchCandidate(start, "magnet:?xt=urn:btih:" + hash));
        }

        // 4. Sort by appearance order in rawText
        candidates.sort(Comparator.comparingInt(a -> a.startIndex));

        // 5. Deduplicate while preserving order
        List<String> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (MatchCandidate cand : candidates) {
            String normalizedKey = cand.url.toLowerCase(Locale.ROOT);
            if (seen.add(normalizedKey)) {
                result.add(cand.url);
            }
        }
        return result;
    }

    /**
     * Defensive sanitization for OpenList/AList token.
     * If a token starts with openlist- or alist- and ends with the literal SQLite column type
     * suffix "string" (i.e., token.endsWith(SQLITE_STRING_TYPE_SUFFIX) && token.length() >= MIN_POLLUTED_TOKEN_LENGTH),
     * strip the trailing "string" automatically.
     */
    public static String sanitizeToken(String token) {
        if (token == null) return "";
        token = token.trim();
        if ((token.startsWith("openlist-") || token.startsWith("alist-"))
                && token.endsWith(SQLITE_STRING_TYPE_SUFFIX)
                && token.length() >= MIN_POLLUTED_TOKEN_LENGTH) {
            token = token.substring(0, token.length() - SQLITE_STRING_TYPE_SUFFIX.length()).trim();
        }
        return token;
    }

    /**
     * Configuration for OpenList offline download.
     */
    public static class OfflineConfig {
        public String host = "127.0.0.1";
        public int port = 5244;
        public String token = "";
        public String path = "/115/影视/";
        public String tool = "115 Open";
        public String deletePolicy = "delete_on_upload_succeed";
        public List<String> presetPaths = new ArrayList<>(Arrays.asList("/115/影视/", "/115/"));

        public OfflineConfig() {}

        public OfflineConfig(String host, int port, String token, String path, String tool, String deletePolicy, List<String> presetPaths) {
            if (host != null && !host.trim().isEmpty()) this.host = host.trim();
            if (port > 0) this.port = port;
            if (token != null) this.token = sanitizeToken(token);
            if (path != null && !path.trim().isEmpty()) this.path = path.trim();
            if (tool != null && !tool.trim().isEmpty()) this.tool = tool.trim();
            if (deletePolicy != null && !deletePolicy.trim().isEmpty()) this.deletePolicy = deletePolicy.trim();
            if (presetPaths != null && !presetPaths.isEmpty()) {
                this.presetPaths = new ArrayList<>(presetPaths);
            }
        }

        public static OfflineConfig parse(String confText) {
            OfflineConfig cfg = new OfflineConfig();
            if (confText == null || confText.trim().isEmpty()) {
                return cfg;
            }
            String[] lines = confText.split("\r?\n");
            for (String line : lines) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                int eq = line.indexOf('=');
                if (eq <= 0) continue;
                String key = line.substring(0, eq).trim().toUpperCase(Locale.ROOT);
                String val = line.substring(eq + 1).trim();
                if ((val.startsWith("\"") && val.endsWith("\"")) || (val.startsWith("'") && val.endsWith("'"))) {
                    if (val.length() >= 2) {
                        val = val.substring(1, val.length() - 1).trim();
                    }
                }
                switch (key) {
                    case "HOST":
                        if (!val.isEmpty()) cfg.host = val;
                        break;
                    case "PORT":
                        try {
                            int p = Integer.parseInt(val);
                            if (p > 0) cfg.port = p;
                        } catch (NumberFormatException ignored) {}
                        break;
                    case "TOKEN":
                        cfg.token = sanitizeToken(val);
                        break;
                    case "PATH":
                        if (!val.isEmpty()) cfg.path = val;
                        break;
                    case "TOOL":
                        if (!val.isEmpty()) cfg.tool = val;
                        break;
                    case "DELETE_POLICY":
                        if (!val.isEmpty()) cfg.deletePolicy = val;
                        break;
                    case "PRESET_PATHS":
                        if (!val.isEmpty()) {
                            String[] paths = val.split(",");
                            List<String> list = new ArrayList<>();
                            for (String p : paths) {
                                p = p.trim();
                                if (!p.isEmpty() && !list.contains(p)) {
                                    list.add(p);
                                }
                            }
                            if (!list.isEmpty()) {
                                cfg.presetPaths = list;
                            }
                        }
                        break;
                }
            }
            return cfg;
        }

        public String serialize() {
            StringBuilder sb = new StringBuilder();
            sb.append("HOST=").append(host != null && !host.isEmpty() ? host : "127.0.0.1").append("\n");
            sb.append("PORT=").append(port > 0 ? port : 5244).append("\n");
            sb.append("TOKEN=").append(token != null ? token : "").append("\n");
            sb.append("PATH=").append(path != null && !path.isEmpty() ? path : "/115/影视/").append("\n");
            sb.append("TOOL=").append(tool != null && !tool.isEmpty() ? tool : "115 Open").append("\n");
            sb.append("DELETE_POLICY=").append(deletePolicy != null && !deletePolicy.isEmpty() ? deletePolicy : "delete_on_upload_succeed").append("\n");
            String presets = (presetPaths != null && !presetPaths.isEmpty()) ? String.join(",", presetPaths) : "/115/影视/,/115/";
            sb.append("PRESET_PATHS=").append(presets).append("\n");
            return sb.toString();
        }

        public static OfflineConfig mergeWithBridge(OfflineConfig bridgeConfig, OfflineConfig userSavedConfig) {
            OfflineConfig merged = new OfflineConfig();

            // 1. Path: Uses userSavedConfig.path if non-empty, else bridgeConfig.path, else "/115/影视/"
            if (userSavedConfig != null && userSavedConfig.path != null && !userSavedConfig.path.trim().isEmpty()) {
                merged.path = userSavedConfig.path.trim();
            } else if (bridgeConfig != null && bridgeConfig.path != null && !bridgeConfig.path.trim().isEmpty()) {
                merged.path = bridgeConfig.path.trim();
            } else {
                merged.path = "/115/影视/";
            }

            // 2. Token: Uses bridgeConfig.token if non-empty (or userSavedConfig.token if user set it when bridge was empty)
            if (bridgeConfig != null && bridgeConfig.token != null && !bridgeConfig.token.trim().isEmpty()) {
                merged.token = sanitizeToken(bridgeConfig.token);
            } else if (userSavedConfig != null && userSavedConfig.token != null && !userSavedConfig.token.trim().isEmpty()) {
                merged.token = sanitizeToken(userSavedConfig.token);
            } else {
                merged.token = "";
            }

            // 3. Port: Uses bridgeConfig.port if valid (>0), else userSavedConfig.port
            if (bridgeConfig != null && bridgeConfig.port > 0) {
                merged.port = bridgeConfig.port;
            } else if (userSavedConfig != null && userSavedConfig.port > 0) {
                merged.port = userSavedConfig.port;
            } else {
                merged.port = 5244;
            }

            // 4. Host
            if (bridgeConfig != null && bridgeConfig.host != null && !bridgeConfig.host.trim().isEmpty()) {
                merged.host = bridgeConfig.host.trim();
            } else if (userSavedConfig != null && userSavedConfig.host != null && !userSavedConfig.host.trim().isEmpty()) {
                merged.host = userSavedConfig.host.trim();
            } else {
                merged.host = "127.0.0.1";
            }

            // 5. Preserves tool ("115 Open") and deletePolicy ("delete_on_upload_succeed")
            merged.tool = (userSavedConfig != null && userSavedConfig.tool != null && !userSavedConfig.tool.trim().isEmpty())
                    ? userSavedConfig.tool.trim()
                    : (bridgeConfig != null && bridgeConfig.tool != null && !bridgeConfig.tool.trim().isEmpty() ? bridgeConfig.tool.trim() : "115 Open");

            merged.deletePolicy = (userSavedConfig != null && userSavedConfig.deletePolicy != null && !userSavedConfig.deletePolicy.trim().isEmpty())
                    ? userSavedConfig.deletePolicy.trim()
                    : (bridgeConfig != null && bridgeConfig.deletePolicy != null && !bridgeConfig.deletePolicy.trim().isEmpty() ? bridgeConfig.deletePolicy.trim() : "delete_on_upload_succeed");

            // 6. Preset paths
            List<String> combined = new ArrayList<>();
            if (userSavedConfig != null && userSavedConfig.presetPaths != null) {
                for (String p : userSavedConfig.presetPaths) {
                    p = p.trim();
                    if (!p.isEmpty() && !combined.contains(p)) combined.add(p);
                }
            }
            if (bridgeConfig != null && bridgeConfig.presetPaths != null) {
                for (String p : bridgeConfig.presetPaths) {
                    p = p.trim();
                    if (!p.isEmpty() && !combined.contains(p)) combined.add(p);
                }
            }
            if (!combined.contains("/115/影视/")) combined.add(0, "/115/影视/");
            if (!combined.contains("/115/")) combined.add("/115/");
            merged.presetPaths = combined;

            return merged;
        }
    }

    /**
     * Escape special characters in a JSON string.
     */
    public static String escapeJson(String s) {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': sb.append("\\\""); break;
                case '\\': sb.append("\\\\"); break;
                case '\b': sb.append("\\b"); break;
                case '\f': sb.append("\\f"); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        sb.append(String.format(Locale.ROOT, "\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
                    break;
            }
        }
        return sb.toString();
    }

    /**
     * Unescape standard JSON string escapes.
     */
    public static String unescapeJson(String s) {
        if (s == null) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\\' && i + 1 < s.length()) {
                char next = s.charAt(i + 1);
                switch (next) {
                    case '"': sb.append('"'); i++; break;
                    case '\\': sb.append('\\'); i++; break;
                    case '/': sb.append('/'); i++; break;
                    case 'b': sb.append('\b'); i++; break;
                    case 'f': sb.append('\f'); i++; break;
                    case 'n': sb.append('\n'); i++; break;
                    case 'r': sb.append('\r'); i++; break;
                    case 't': sb.append('\t'); i++; break;
                    case 'u':
                        if (i + 5 < s.length()) {
                            String hex = s.substring(i + 2, i + 6);
                            try {
                                sb.append((char) Integer.parseInt(hex, 16));
                                i += 5;
                                break;
                            } catch (NumberFormatException ignored) {}
                        }
                        sb.append(c);
                        break;
                    default:
                        sb.append(c);
                        break;
                }
            } else {
                sb.append(c);
            }
        }
        return sb.toString();
    }

    /**
     * Builds request payload for OpenList /api/fs/add_offline_download from an OfflineConfig.
     */
    public static String buildRequestPayload(List<String> urls, OfflineConfig config) {
        String path = (config != null) ? config.path : "/115/影视/";
        String tool = (config != null) ? config.tool : "115 Open";
        String deletePolicy = (config != null) ? config.deletePolicy : "delete_on_upload_succeed";
        return buildRequestPayload(urls, path, tool, deletePolicy);
    }

    /**
     * Builds request payload for OpenList /api/fs/add_offline_download.
     */
    public static String buildRequestPayload(List<String> urls, String path, String tool, String deletePolicy) {
        StringBuilder sb = new StringBuilder();
        sb.append("{\"urls\":[");
        if (urls != null) {
            for (int i = 0; i < urls.size(); i++) {
                if (i > 0) sb.append(",");
                sb.append("\"").append(escapeJson(urls.get(i))).append("\"");
            }
        }
        sb.append("],\"path\":\"").append(escapeJson(path != null && !path.isEmpty() ? path : "/115/影视/")).append("\",");
        sb.append("\"tool\":\"").append(escapeJson(tool != null && !tool.isEmpty() ? tool : "115 Open")).append("\",");
        sb.append("\"delete_policy\":\"").append(escapeJson(deletePolicy != null && !deletePolicy.isEmpty() ? deletePolicy : "delete_on_upload_succeed")).append("\"}");
        return sb.toString();
    }

    /**
     * Result of an API call to OpenList daemon.
     */
    public static class ApiResult {
        public final boolean success;
        public final int code;
        public final String message;
        public final String rawBody;

        public ApiResult(boolean success, int code, String message, String rawBody) {
            this.success = success;
            this.code = code;
            this.message = message != null ? message : "";
            this.rawBody = rawBody != null ? rawBody : "";
        }

        public boolean isStorageError() {
            if (success) return false;
            String combined = ((message != null ? message : "") + " " + (rawBody != null ? rawBody : "")).toLowerCase(Locale.ROOT);
            return combined.contains("storage") || combined.contains("not init") || combined.contains("disabled");
        }

        @Override
        public String toString() {
            return "ApiResult{success=" + success + ", code=" + code + ", message='" + message + "'}";
        }
    }

    /**
     * Submits offline download URLs to OpenList daemon using OfflineConfig.
     */
    public static ApiResult submitOfflineDownload(List<String> urls, OfflineConfig config, int timeoutMs) {
        String host = (config != null && config.host != null && !config.host.isEmpty()) ? config.host : "127.0.0.1";
        int port = (config != null && config.port > 0) ? config.port : 5244;
        String baseUrl = "http://" + host + ":" + port;
        String token = (config != null) ? sanitizeToken(config.token) : "";
        String path = (config != null) ? config.path : "/115/影视/";
        String tool = (config != null) ? config.tool : "115 Open";
        String deletePolicy = (config != null) ? config.deletePolicy : "delete_on_upload_succeed";
        return submitOfflineDownload(baseUrl, token, urls, path, tool, deletePolicy, timeoutMs);
    }

    /**
     * Reloads all storages by calling OpenList /api/admin/storage/load_all.
     * Useful when 115 Open storage was initialized before Wi-Fi DNS was available.
     */
    public static boolean reloadAllStorage(String baseUrl, String token, int timeoutMs) {
        if (baseUrl == null || baseUrl.trim().isEmpty()) {
            baseUrl = "http://127.0.0.1:5244";
        }
        if (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        String endpoint = baseUrl + "/api/admin/storage/load_all";
        HttpURLConnection conn = null;
        try {
            URL url = new URL(endpoint);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(timeoutMs > 0 ? timeoutMs : 10000);
            conn.setReadTimeout(timeoutMs > 0 ? timeoutMs : 10000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            String sanitized = sanitizeToken(token);
            if (!sanitized.isEmpty()) {
                conn.setRequestProperty("Authorization", sanitized);
            }

            byte[] bodyBytes = "{}".getBytes(StandardCharsets.UTF_8);
            conn.setRequestProperty("Content-Length", String.valueOf(bodyBytes.length));
            try (OutputStream os = conn.getOutputStream()) {
                os.write(bodyBytes);
                os.flush();
            }

            int httpCode = conn.getResponseCode();
            InputStream rawStream = (httpCode >= 200 && httpCode < 400) ? conn.getInputStream() : conn.getErrorStream();
            if (rawStream != null) {
                try (InputStream is = rawStream; ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                    byte[] buf = new byte[1024];
                    int len;
                    while ((len = is.read(buf)) != -1) {
                        baos.write(buf, 0, len);
                    }
                }
            }
            return (httpCode == 200);
        } catch (Exception ignored) {
            return false;
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    /**
     * Submits offline download URLs to OpenList daemon.
     * Automatically attempts recovery via /api/admin/storage/load_all if storage is uninitialized.
     */
    public static ApiResult submitOfflineDownload(String baseUrl, String token, List<String> urls, String path, String tool, String deletePolicy, int timeoutMs) {
        String sanitizedToken = sanitizeToken(token);
        ApiResult res = executeAddOfflineDownload(baseUrl, sanitizedToken, urls, path, tool, deletePolicy, timeoutMs);

        // Auto-heal: if code != 200 and message contains storage/not init/disabled, reload storage and retry once
        if (!res.success && res.isStorageError()) {
            reloadAllStorage(baseUrl, sanitizedToken, timeoutMs);
            try {
                Thread.sleep(800);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            res = executeAddOfflineDownload(baseUrl, sanitizedToken, urls, path, tool, deletePolicy, timeoutMs);
        }

        // Best-effort cache invalidation on success
        if (res.success) {
            try {
                refreshDirectoryCache(baseUrl, sanitizedToken, path, timeoutMs);
            } catch (Exception ignored) {
                // Best-effort cache invalidation, never alter or fail res
            }
        }

        return res;
    }

    private static ApiResult executeAddOfflineDownload(String baseUrl, String token, List<String> urls, String path, String tool, String deletePolicy, int timeoutMs) {
        if (baseUrl == null || baseUrl.trim().isEmpty()) {
            baseUrl = "http://127.0.0.1:5244";
        }
        if (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        String endpoint = baseUrl + "/api/fs/add_offline_download";
        String payload = buildRequestPayload(urls, path, tool, deletePolicy);
        HttpURLConnection conn = null;
        try {
            URL url = new URL(endpoint);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(timeoutMs > 0 ? timeoutMs : 10000);
            conn.setReadTimeout(timeoutMs > 0 ? timeoutMs : 10000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            String sanitizedToken = sanitizeToken(token);
            if (!sanitizedToken.isEmpty()) {
                conn.setRequestProperty("Authorization", sanitizedToken);
            }

            byte[] bodyBytes = payload.getBytes(StandardCharsets.UTF_8);
            conn.setRequestProperty("Content-Length", String.valueOf(bodyBytes.length));
            try (OutputStream os = conn.getOutputStream()) {
                os.write(bodyBytes);
                os.flush();
            }

            int httpCode = conn.getResponseCode();
            InputStream rawStream = (httpCode >= 200 && httpCode < 400) ? conn.getInputStream() : conn.getErrorStream();
            String responseBody = "";
            if (rawStream != null) {
                try (InputStream is = rawStream; ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                    byte[] buf = new byte[1024];
                    int len;
                    while ((len = is.read(buf)) != -1) {
                        baos.write(buf, 0, len);
                    }
                    responseBody = baos.toString("UTF-8");
                }
            }

            int jsonCode = -1;
            String jsonMsg = "";

            Matcher codeMatcher = Pattern.compile("\"code\"\\s*:\\s*(-?\\d+)").matcher(responseBody);
            if (codeMatcher.find()) {
                try {
                    jsonCode = Integer.parseInt(codeMatcher.group(1));
                } catch (NumberFormatException ignored) {}
            }

            Matcher msgMatcher = Pattern.compile("\"message\"\\s*:\\s*\"([^\"]*)\"").matcher(responseBody);
            if (msgMatcher.find()) {
                jsonMsg = unescapeJson(msgMatcher.group(1));
            } else {
                jsonMsg = "HTTP " + httpCode + (responseBody.isEmpty() ? "" : ": " + responseBody);
            }

            boolean success = (httpCode == 200) && (jsonCode == 200);
            return new ApiResult(success, jsonCode >= 0 ? jsonCode : httpCode, jsonMsg, responseBody);
        } catch (Exception e) {
            return new ApiResult(false, -1, e.getClass().getSimpleName() + ": " + e.getMessage(), "");
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }

    /**
     * Normalizes a virtual path for OpenList navigation and display.
     * Null, empty or whitespace defaults to "/".
     * Trims whitespace, converts backslashes to slashes, ensures leading slash,
     * collapses consecutive slashes, and ensures trailing slash.
     */
    public static String normalizeVirtualPath(String path) {
        if (path == null) {
            return "/";
        }
        path = path.trim();
        if (path.isEmpty()) {
            return "/";
        }
        path = path.replace('\\', '/');
        if (!path.startsWith("/")) {
            path = "/" + path;
        }
        path = path.replaceAll("/+", "/");
        if (!path.endsWith("/")) {
            path = path + "/";
        }
        return path;
    }

    /**
     * Returns the parent directory virtual path, ending with a trailing slash.
     * Root "/" returns "/".
     * E.g. "/115/影视/" -> "/115/", "/115/" -> "/".
     */
    public static String parentVirtualPath(String path) {
        String normalized = normalizeVirtualPath(path);
        if ("/".equals(normalized)) {
            return "/";
        }
        String stripped = normalized.substring(0, normalized.length() - 1);
        int lastSlash = stripped.lastIndexOf('/');
        if (lastSlash < 0) {
            return "/";
        }
        return stripped.substring(0, lastSlash + 1);
    }

    /**
     * Joins parentPath and childDirName into a normalized directory path ending with a trailing slash.
     * E.g. joinVirtualPath("/115/", "影视") -> "/115/影视/".
     */
    public static String joinVirtualPath(String parentPath, String childDirName) {
        String parent = normalizeVirtualPath(parentPath);
        if (childDirName == null || childDirName.trim().isEmpty()) {
            return parent;
        }
        String combined = parent + childDirName.trim();
        return normalizeVirtualPath(combined);
    }

    /**
     * Builds request payload for OpenList /api/fs/list with default refresh=false.
     * Root path is "/", non-root paths have their trailing slash stripped.
     */
    public static String buildListDirectoryPayload(String path) {
        return buildListDirectoryPayload(path, false);
    }

    /**
     * Builds request payload for OpenList /api/fs/list with specified refresh flag.
     * Root path is "/", non-root paths have their trailing slash stripped.
     */
    public static String buildListDirectoryPayload(String path, boolean refresh) {
        String normalized = normalizeVirtualPath(path);
        String apiPath = "/".equals(normalized) ? "/" : (normalized.endsWith("/") ? normalized.substring(0, normalized.length() - 1) : normalized);
        return "{\"path\":\"" + escapeJson(apiPath) + "\",\"password\":\"\",\"page\":1,\"per_page\":0,\"refresh\":" + (refresh ? "true" : "false") + "}";
    }

    /**
     * Result of listing a directory from OpenList daemon.
     */
    public static class DirListResult {
        public final boolean success;
        public final int code;
        public final String message;
        public final String currentPath;
        public final List<String> directories;
        public final String rawBody;

        public DirListResult(boolean success, int code, String message, String currentPath, List<String> directories, String rawBody) {
            this.success = success;
            this.code = code;
            this.message = message != null ? message : "";
            this.currentPath = currentPath != null ? currentPath : "/";
            this.directories = (directories != null) ? Collections.unmodifiableList(new ArrayList<>(directories)) : Collections.emptyList();
            this.rawBody = rawBody != null ? rawBody : "";
        }

        public boolean isStorageError() {
            if (success) return false;
            String combined = ((message != null ? message : "") + " " + (rawBody != null ? rawBody : "")).toLowerCase(Locale.ROOT);
            return combined.contains("storage") || combined.contains("not init") || combined.contains("disabled");
        }

        @Override
        public String toString() {
            return "DirListResult{success=" + success + ", code=" + code + ", currentPath='" + currentPath + "', dirs=" + directories.size() + "}";
        }
    }

    /**
     * Parses directory names from OpenList /api/fs/list response JSON.
     * Extracts items with "is_dir": true from "content": [ ... ], decodes their "name",
     * preserves appearance order, and deduplicates.
     */
    public static List<String> parseDirectoryNamesFromListJson(String jsonBody) {
        if (jsonBody == null || jsonBody.trim().isEmpty()) {
            return Collections.emptyList();
        }
        if (Pattern.compile("\"content\"\\s*:\\s*null\\b").matcher(jsonBody).find()) {
            return Collections.emptyList();
        }

        String searchScope = jsonBody;
        Matcher contentMatcher = Pattern.compile("\"content\"\\s*:\\s*\\[").matcher(jsonBody);
        if (contentMatcher.find()) {
            int arrayStart = contentMatcher.end() - 1;
            int depth = 0;
            boolean inStr = false;
            boolean escape = false;
            int arrayEnd = -1;
            for (int i = arrayStart; i < jsonBody.length(); i++) {
                char c = jsonBody.charAt(i);
                if (escape) {
                    escape = false;
                    continue;
                }
                if (c == '\\') {
                    if (inStr) escape = true;
                    continue;
                }
                if (c == '"') {
                    inStr = !inStr;
                    continue;
                }
                if (!inStr) {
                    if (c == '[') depth++;
                    else if (c == ']') {
                        depth--;
                        if (depth == 0) {
                            arrayEnd = i;
                            break;
                        }
                    }
                }
            }
            if (arrayEnd > arrayStart) {
                searchScope = jsonBody.substring(arrayStart + 1, arrayEnd);
            }
        } else {
            int firstBracket = jsonBody.indexOf('[');
            if (firstBracket >= 0) {
                int depth = 0;
                boolean inStr = false;
                boolean escape = false;
                int arrayEnd = -1;
                for (int i = firstBracket; i < jsonBody.length(); i++) {
                    char c = jsonBody.charAt(i);
                    if (escape) {
                        escape = false;
                        continue;
                    }
                    if (c == '\\') {
                        if (inStr) escape = true;
                        continue;
                    }
                    if (c == '"') {
                        inStr = !inStr;
                        continue;
                    }
                    if (!inStr) {
                        if (c == '[') depth++;
                        else if (c == ']') {
                            depth--;
                            if (depth == 0) {
                                arrayEnd = i;
                                break;
                            }
                        }
                    }
                }
                if (arrayEnd > firstBracket) {
                    searchScope = jsonBody.substring(firstBracket + 1, arrayEnd);
                }
            }
        }

        List<String> objectBlocks = new ArrayList<>();
        int depth = 0;
        int objStart = -1;
        boolean inStr = false;
        boolean escape = false;
        for (int i = 0; i < searchScope.length(); i++) {
            char c = searchScope.charAt(i);
            if (escape) {
                escape = false;
                continue;
            }
            if (c == '\\') {
                if (inStr) escape = true;
                continue;
            }
            if (c == '"') {
                inStr = !inStr;
                continue;
            }
            if (!inStr) {
                if (c == '{') {
                    if (depth == 0) {
                        objStart = i;
                    }
                    depth++;
                } else if (c == '}') {
                    depth--;
                    if (depth == 0 && objStart != -1) {
                        objectBlocks.add(searchScope.substring(objStart, i + 1));
                        objStart = -1;
                    }
                }
            }
        }

        Pattern isDirPattern = Pattern.compile("\"is_dir\"\\s*:\\s*(?:true|\"true\")\\b", Pattern.CASE_INSENSITIVE);
        Pattern namePattern = Pattern.compile("\"name\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"");

        List<String> result = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (String block : objectBlocks) {
            if (!isDirPattern.matcher(block).find()) {
                continue;
            }
            Matcher nameMatcher = namePattern.matcher(block);
            if (nameMatcher.find()) {
                String unescaped = unescapeJson(nameMatcher.group(1));
                if (seen.add(unescaped)) {
                    result.add(unescaped);
                }
            }
        }
        return result;
    }

    /**
     * Lists subdirectories for a given virtual path using OfflineConfig (cached, refresh=false).
     */
    public static DirListResult listDirectories(String path, OfflineConfig config, int timeoutMs) {
        return listDirectories(path, config, false, timeoutMs);
    }

    /**
     * Lists subdirectories for a given virtual path using OfflineConfig with optional forced refresh.
     */
    public static DirListResult listDirectories(String path, OfflineConfig config, boolean refresh, int timeoutMs) {
        String host = (config != null && config.host != null && !config.host.isEmpty()) ? config.host : "127.0.0.1";
        int port = (config != null && config.port > 0) ? config.port : 5244;
        String baseUrl = "http://" + host + ":" + port;
        String token = (config != null) ? sanitizeToken(config.token) : "";
        return listDirectories(baseUrl, token, path, refresh, timeoutMs);
    }

    /**
     * Lists subdirectories for a given virtual path from OpenList daemon (cached, refresh=false).
     * Automatically attempts recovery via /api/admin/storage/load_all if storage is uninitialized.
     */
    public static DirListResult listDirectories(String baseUrl, String token, String path, int timeoutMs) {
        return listDirectories(baseUrl, token, path, false, timeoutMs);
    }

    /**
     * Lists subdirectories for a given virtual path from OpenList daemon with optional forced refresh.
     * Automatically attempts recovery via /api/admin/storage/load_all if storage is uninitialized.
     */
    public static DirListResult listDirectories(String baseUrl, String token, String path, boolean refresh, int timeoutMs) {
        String sanitizedToken = sanitizeToken(token);
        String normalizedPath = normalizeVirtualPath(path);
        DirListResult res = executeListDirectories(baseUrl, sanitizedToken, normalizedPath, refresh, timeoutMs);

        // Auto-heal: if code != 200 and error indicates storage not init/disabled, reload storage and retry once
        if (!res.success && res.isStorageError()) {
            reloadAllStorage(baseUrl, sanitizedToken, timeoutMs);
            try {
                Thread.sleep(800);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            res = executeListDirectories(baseUrl, sanitizedToken, normalizedPath, refresh, timeoutMs);
        }

        return res;
    }

    /**
     * Forces OpenList to refresh its directory cache for the given path using OfflineConfig.
     * Invokes /api/fs/list with refresh=true.
     * Returns true if the refresh succeeded.
     */
    public static boolean refreshDirectoryCache(String path, OfflineConfig config, int timeoutMs) {
        DirListResult res = listDirectories(path, config, true, timeoutMs);
        return res != null && res.success;
    }

    /**
     * Forces OpenList to refresh its directory cache for the given path from OpenList daemon.
     * Invokes /api/fs/list with refresh=true.
     * Returns true if the refresh succeeded.
     */
    public static boolean refreshDirectoryCache(String baseUrl, String token, String path, int timeoutMs) {
        DirListResult res = listDirectories(baseUrl, token, path, true, timeoutMs);
        return res != null && res.success;
    }

    private static DirListResult executeListDirectories(String baseUrl, String token, String normalizedPath, boolean refresh, int timeoutMs) {
        if (baseUrl == null || baseUrl.trim().isEmpty()) {
            baseUrl = "http://127.0.0.1:5244";
        }
        if (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        String endpoint = baseUrl + "/api/fs/list";
        String payload = buildListDirectoryPayload(normalizedPath, refresh);
        HttpURLConnection conn = null;
        try {
            URL url = new URL(endpoint);
            conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(timeoutMs > 0 ? timeoutMs : 10000);
            conn.setReadTimeout(timeoutMs > 0 ? timeoutMs : 10000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            String sanitizedToken = sanitizeToken(token);
            if (!sanitizedToken.isEmpty()) {
                conn.setRequestProperty("Authorization", sanitizedToken);
            }

            byte[] bodyBytes = payload.getBytes(StandardCharsets.UTF_8);
            conn.setRequestProperty("Content-Length", String.valueOf(bodyBytes.length));
            try (OutputStream os = conn.getOutputStream()) {
                os.write(bodyBytes);
                os.flush();
            }

            int httpCode = conn.getResponseCode();
            InputStream rawStream = (httpCode >= 200 && httpCode < 400) ? conn.getInputStream() : conn.getErrorStream();
            String responseBody = "";
            if (rawStream != null) {
                try (InputStream is = rawStream; ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                    byte[] buf = new byte[1024];
                    int len;
                    while ((len = is.read(buf)) != -1) {
                        baos.write(buf, 0, len);
                    }
                    responseBody = baos.toString("UTF-8");
                }
            }

            int jsonCode = -1;
            String jsonMsg = "";

            Matcher codeMatcher = Pattern.compile("\"code\"\\s*:\\s*(-?\\d+)").matcher(responseBody);
            if (codeMatcher.find()) {
                try {
                    jsonCode = Integer.parseInt(codeMatcher.group(1));
                } catch (NumberFormatException ignored) {}
            }

            Matcher msgMatcher = Pattern.compile("\"message\"\\s*:\\s*\"([^\"]*)\"").matcher(responseBody);
            if (msgMatcher.find()) {
                jsonMsg = unescapeJson(msgMatcher.group(1));
            } else {
                jsonMsg = "HTTP " + httpCode + (responseBody.isEmpty() ? "" : ": " + responseBody);
            }

            boolean success = (httpCode == 200) && (jsonCode == 200);
            List<String> directories = success ? parseDirectoryNamesFromListJson(responseBody) : Collections.emptyList();
            return new DirListResult(success, jsonCode >= 0 ? jsonCode : httpCode, jsonMsg, normalizedPath, directories, responseBody);
        } catch (Exception e) {
            return new DirListResult(false, -1, e.getClass().getSimpleName() + ": " + e.getMessage(), normalizedPath, Collections.emptyList(), "");
        } finally {
            if (conn != null) {
                conn.disconnect();
            }
        }
    }
}
