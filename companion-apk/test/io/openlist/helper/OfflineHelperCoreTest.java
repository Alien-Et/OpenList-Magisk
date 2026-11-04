package io.openlist.helper;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

public class OfflineHelperCoreTest {

    private static int testsRun = 0;
    private static int testsPassed = 0;

    public static void main(String[] args) {
        System.out.println("=== Starting OfflineHelperCoreTest ===");

        runTest("testSingleMagnetExtraction", OfflineHelperCoreTest::testSingleMagnetExtraction);
        runTest("testMultiMagnetExtraction", OfflineHelperCoreTest::testMultiMagnetExtraction);
        runTest("testHexHashNormalization", OfflineHelperCoreTest::testHexHashNormalization);
        runTest("testBase32HashNormalization", OfflineHelperCoreTest::testBase32HashNormalization);
        runTest("testDeduplicationAndHashInsideMagnet", OfflineHelperCoreTest::testDeduplicationAndHashInsideMagnet);
        runTest("testEmptyAndNullTextExtraction", OfflineHelperCoreTest::testEmptyAndNullTextExtraction);
        runTest("testConfigParsingAndSerialization", OfflineHelperCoreTest::testConfigParsingAndSerialization);
        runTest("testConfigMergeWithBridge", OfflineHelperCoreTest::testConfigMergeWithBridge);
        runTest("testJsonPayloadEscaping", OfflineHelperCoreTest::testJsonPayloadEscaping);
        runTest("testMockHttpServerSuccessAndFailure", OfflineHelperCoreTest::testMockHttpServerSuccessAndFailure);
        runTest("testConfigBasedPayloadAndSubmit", OfflineHelperCoreTest::testConfigBasedPayloadAndSubmit);
        runTest("testTokenSanitization", OfflineHelperCoreTest::testTokenSanitization);
        runTest("testApiResultIsStorageError", OfflineHelperCoreTest::testApiResultIsStorageError);
        runTest("testAutoHealStorageNotInit", OfflineHelperCoreTest::testAutoHealStorageNotInit);
        runTest("testManifestDefaultDisabledProcessTextActivity", OfflineHelperCoreTest::testManifestDefaultDisabledProcessTextActivity);
        runTest("testVirtualPathHelpers", OfflineHelperCoreTest::testVirtualPathHelpers);
        runTest("testParseDirectoryNamesFromListJson", OfflineHelperCoreTest::testParseDirectoryNamesFromListJson);
        runTest("testListDirectoriesMockHttpAndAutoHeal", OfflineHelperCoreTest::testListDirectoriesMockHttpAndAutoHeal);

        System.out.println("=== Test Summary: " + testsPassed + "/" + testsRun + " passed ===");
        if (testsPassed != testsRun) {
            System.err.println("SOME TESTS FAILED!");
            System.exit(1);
        } else {
            System.out.println("ALL TESTS PASSED SUCCESSFULLY!");
        }
    }

    private static void runTest(String name, TestCase test) {
        testsRun++;
        try {
            test.run();
            testsPassed++;
            System.out.println("  [PASS] " + name);
        } catch (Throwable t) {
            System.err.println("  [FAIL] " + name + ": " + t.getMessage());
            t.printStackTrace(System.err);
        }
    }

    @FunctionalInterface
    interface TestCase {
        void run() throws Throwable;
    }

    private static void assertTrue(boolean condition, String msg) {
        if (!condition) throw new AssertionError("Assertion failed: " + msg);
    }

    private static void assertEquals(Object expected, Object actual, String msg) {
        if (expected == null && actual == null) return;
        if (expected != null && expected.equals(actual)) return;
        throw new AssertionError("Assertion failed [" + msg + "]: expected <" + expected + "> but got <" + actual + ">");
    }

    private static void testSingleMagnetExtraction() {
        String text = "Check this download link: magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Ubuntu and enjoy.";
        List<String> urls = OfflineHelperCore.extractMagnetUrls(text);
        assertEquals(1, urls.size(), "Should extract 1 magnet URL");
        assertEquals("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Ubuntu", urls.get(0), "URL match");

        // Trailing sentence punctuation removal
        String textTrailing = "Here: magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567.";
        List<String> urlsTrailing = OfflineHelperCore.extractMagnetUrls(textTrailing);
        assertEquals(1, urlsTrailing.size(), "Should extract 1 URL");
        assertEquals("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567", urlsTrailing.get(0), "Trailing dot stripped");
    }

    private static void testMultiMagnetExtraction() {
        String text = "First link: magnet:?xt=urn:btih:1111111111111111111111111111111111111111 and second link: magnet:?xt=urn:btih:2222222222222222222222222222222222222222";
        List<String> urls = OfflineHelperCore.extractMagnetUrls(text);
        assertEquals(2, urls.size(), "Should extract 2 magnet URLs");
        assertEquals("magnet:?xt=urn:btih:1111111111111111111111111111111111111111", urls.get(0), "First URL");
        assertEquals("magnet:?xt=urn:btih:2222222222222222222222222222222222222222", urls.get(1), "Second URL");
    }

    private static void testHexHashNormalization() {
        String text = "Standalone hash: 4a3b2c1d0e4a3b2c1d0e4a3b2c1d0e4a3b2c1d0e in text";
        List<String> urls = OfflineHelperCore.extractMagnetUrls(text);
        assertEquals(1, urls.size(), "Should extract 1 hex hash as magnet");
        assertEquals("magnet:?xt=urn:btih:4a3b2c1d0e4a3b2c1d0e4a3b2c1d0e4a3b2c1d0e", urls.get(0), "Normalized hex magnet");

        // Case insensitive hex hash
        String upperText = "UPPERCASE: 4A3B2C1D0E4A3B2C1D0E4A3B2C1D0E4A3B2C1D0E";
        List<String> upperUrls = OfflineHelperCore.extractMagnetUrls(upperText);
        assertEquals(1, upperUrls.size(), "Should extract 1 uppercase hex hash");
        assertEquals("magnet:?xt=urn:btih:4A3B2C1D0E4A3B2C1D0E4A3B2C1D0E4A3B2C1D0E", upperUrls.get(0), "Normalized uppercase hex magnet");
    }

    private static void testBase32HashNormalization() {
        String text = "Torrent base32: 4WPH7DGLZ63Z7A76ZXZN2V3F7X3V4YZA available here";
        List<String> urls = OfflineHelperCore.extractMagnetUrls(text);
        assertEquals(1, urls.size(), "Should extract 1 base32 hash as magnet");
        assertEquals("magnet:?xt=urn:btih:4WPH7DGLZ63Z7A76ZXZN2V3F7X3V4YZA", urls.get(0), "Normalized base32 magnet");
    }

    private static void testDeduplicationAndHashInsideMagnet() {
        // Text contains a full magnet, a standalone hash that matches the magnet's hash, and a duplicate magnet
        String hash = "0123456789abcdef0123456789abcdef01234567";
        String magnet = "magnet:?xt=urn:btih:" + hash + "&dn=Movie";
        String text = "Link: " + magnet + " Hash again: " + hash + " Duplicate link: " + magnet;

        List<String> urls = OfflineHelperCore.extractMagnetUrls(text);
        assertEquals(1, urls.size(), "Should deduplicate and ignore hash that is inside magnet");
        assertEquals(magnet, urls.get(0), "Only original full magnet retained");
    }

    private static void testEmptyAndNullTextExtraction() {
        assertEquals(0, OfflineHelperCore.extractMagnetUrls(null).size(), "Null text");
        assertEquals(0, OfflineHelperCore.extractMagnetUrls("").size(), "Empty text");
        assertEquals(0, OfflineHelperCore.extractMagnetUrls("   \t\n  ").size(), "Whitespace text");
        assertEquals(0, OfflineHelperCore.extractMagnetUrls("Hello world no magnet here!").size(), "Normal text without magnet");
    }

    private static void testConfigParsingAndSerialization() {
        // Defaults
        OfflineHelperCore.OfflineConfig def = new OfflineHelperCore.OfflineConfig();
        assertEquals("127.0.0.1", def.host, "Default host");
        assertEquals(5244, def.port, "Default port");
        assertEquals("", def.token, "Default token");
        assertEquals("/115/影视/", def.path, "Default path");
        assertEquals("115 Open", def.tool, "Default tool");
        assertEquals("delete_on_upload_succeed", def.deletePolicy, "Default deletePolicy");
        assertTrue(def.presetPaths.contains("/115/影视/"), "Default preset /115/影视/");
        assertTrue(def.presetPaths.contains("/115/"), "Default preset /115/");

        // Parsing
        String conf = "# Comment line\n" +
                "HOST=192.168.1.50\n" +
                "PORT=5245\n" +
                "TOKEN=openlist-token-xyz\n" +
                "PATH=/115/动漫/\n" +
                "TOOL=115 Open\n" +
                "DELETE_POLICY=delete_on_upload_succeed\n" +
                "PRESET_PATHS=/115/动漫/,/115/电影/,/115/\n";

        OfflineHelperCore.OfflineConfig parsed = OfflineHelperCore.OfflineConfig.parse(conf);
        assertEquals("192.168.1.50", parsed.host, "Parsed host");
        assertEquals(5245, parsed.port, "Parsed port");
        assertEquals("openlist-token-xyz", parsed.token, "Parsed token");
        assertEquals("/115/动漫/", parsed.path, "Parsed path");
        assertEquals("115 Open", parsed.tool, "Parsed tool");
        assertEquals("delete_on_upload_succeed", parsed.deletePolicy, "Parsed deletePolicy");
        assertEquals(3, parsed.presetPaths.size(), "Parsed presets count");
        assertEquals("/115/动漫/", parsed.presetPaths.get(0), "Preset 0");

        // Roundtrip serialization
        String serialized = parsed.serialize();
        OfflineHelperCore.OfflineConfig roundtrip = OfflineHelperCore.OfflineConfig.parse(serialized);
        assertEquals(parsed.host, roundtrip.host, "Roundtrip host");
        assertEquals(parsed.port, roundtrip.port, "Roundtrip port");
        assertEquals(parsed.token, roundtrip.token, "Roundtrip token");
        assertEquals(parsed.path, roundtrip.path, "Roundtrip path");
        assertEquals(parsed.tool, roundtrip.tool, "Roundtrip tool");
        assertEquals(parsed.deletePolicy, roundtrip.deletePolicy, "Roundtrip deletePolicy");
        assertEquals(parsed.presetPaths, roundtrip.presetPaths, "Roundtrip presetPaths");
    }

    private static void testConfigMergeWithBridge() {
        OfflineHelperCore.OfflineConfig bridge = new OfflineHelperCore.OfflineConfig();
        bridge.host = "127.0.0.1";
        bridge.port = 5244;
        bridge.token = "bridge_secret_token";
        bridge.path = "/115/影视/";

        OfflineHelperCore.OfflineConfig user = new OfflineHelperCore.OfflineConfig();
        user.path = "/115/纪录片/";
        user.token = ""; // User didn't set token

        // Case 1: user path overrides bridge path, bridge token taken
        OfflineHelperCore.OfflineConfig merged = OfflineHelperCore.OfflineConfig.mergeWithBridge(bridge, user);
        assertEquals("/115/纪录片/", merged.path, "User path overrides bridge path");
        assertEquals("bridge_secret_token", merged.token, "Bridge token used when non-empty");
        assertEquals(5244, merged.port, "Bridge port used");
        assertEquals("115 Open", merged.tool, "Tool preserved");
        assertEquals("delete_on_upload_succeed", merged.deletePolicy, "DeletePolicy preserved");

        // Case 2: bridge token empty, user token used
        bridge.token = "";
        user.token = "user_manual_token";
        OfflineHelperCore.OfflineConfig merged2 = OfflineHelperCore.OfflineConfig.mergeWithBridge(bridge, user);
        assertEquals("user_manual_token", merged2.token, "User token used when bridge token is empty");

        // Case 3: user has empty path, falls back to bridge path
        user.path = "";
        bridge.path = "/115/影视/";
        OfflineHelperCore.OfflineConfig merged3 = OfflineHelperCore.OfflineConfig.mergeWithBridge(bridge, user);
        assertEquals("/115/影视/", merged3.path, "Bridge path used when user path is empty");
    }

    private static void testJsonPayloadEscaping() {
        List<String> urls = Arrays.asList(
                "magnet:?xt=urn:btih:1234567890123456789012345678901234567890&dn=Test%20File",
                "magnet:?xt=urn:btih:abcdefabcdefabcdefabcdefabcdefabcdefabcd&dn=Quote\"And\\Slash"
        );
        String payload = OfflineHelperCore.buildRequestPayload(urls, "/115/特殊\"路径/", "115 Open", "delete_on_upload_succeed");

        assertTrue(payload.startsWith("{\"urls\":["), "Payload starts with urls");
        assertTrue(payload.contains("\"path\":\"/115/特殊\\\"路径/\""), "Path properly escaped");
        assertTrue(payload.contains("\"tool\":\"115 Open\""), "Tool included");
        assertTrue(payload.contains("\"delete_policy\":\"delete_on_upload_succeed\""), "Delete policy included");
        assertTrue(payload.contains("Quote\\\"And\\\\Slash"), "URL string escaped");
    }

    private static void testMockHttpServerSuccessAndFailure() throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int port = server.getAddress().getPort();

        AtomicBoolean requestReceived = new AtomicBoolean(false);
        AtomicReference<String> receivedAuth = new AtomicReference<>("");
        AtomicReference<String> receivedBody = new AtomicReference<>("");
        AtomicReference<String> responseToReturn = new AtomicReference<>("{\"code\":200,\"message\":\"success\",\"data\":null}");
        AtomicReference<Integer> httpStatusToReturn = new AtomicReference<>(200);

        server.createContext("/api/fs/add_offline_download", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                requestReceived.set(true);
                receivedAuth.set(exchange.getRequestHeaders().getFirst("Authorization"));

                try (InputStream is = exchange.getRequestBody();
                     ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                    byte[] buf = new byte[1024];
                    int len;
                    while ((len = is.read(buf)) != -1) {
                        baos.write(buf, 0, len);
                    }
                    receivedBody.set(baos.toString(StandardCharsets.UTF_8.name()));
                }

                byte[] respBytes = responseToReturn.get().getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
                exchange.sendResponseHeaders(httpStatusToReturn.get(), respBytes.length);
                try (OutputStream os = exchange.getResponseBody()) {
                    os.write(respBytes);
                    os.flush();
                }
            }
        });

        server.start();

        try {
            List<String> urls = Collections.singletonList("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567");

            // 1. Test Success
            OfflineHelperCore.ApiResult resSuccess = OfflineHelperCore.submitOfflineDownload(
                    "http://127.0.0.1:" + port,
                    "test_openlist_token",
                    urls,
                    "/115/影视/",
                    "115 Open",
                    "delete_on_upload_succeed",
                    5000
            );

            assertTrue(requestReceived.get(), "Server received request");
            assertEquals("test_openlist_token", receivedAuth.get(), "Auth header matched");
            assertTrue(receivedBody.get().contains("0123456789abcdef0123456789abcdef01234567"), "Request body contains url");
            assertTrue(resSuccess.success, "Result success is true");
            assertEquals(200, resSuccess.code, "Result code is 200");
            assertEquals("success", resSuccess.message, "Result message is success");

            // 2. Test OpenList API Error (HTTP 200, but JSON code 500)
            responseToReturn.set("{\"code\":500,\"message\":\"115 offline quota reached\",\"data\":null}");
            httpStatusToReturn.set(200);

            OfflineHelperCore.ApiResult resApiError = OfflineHelperCore.submitOfflineDownload(
                    "http://127.0.0.1:" + port,
                    "test_openlist_token",
                    urls,
                    "/115/影视/",
                    "115 Open",
                    "delete_on_upload_succeed",
                    5000
            );

            assertTrue(!resApiError.success, "API error result success must be false");
            assertEquals(500, resApiError.code, "API error code must be 500");
            assertEquals("115 offline quota reached", resApiError.message, "API error message match");

            // 3. Test HTTP 401 Unauthorized
            responseToReturn.set("{\"code\":401,\"message\":\"Invalid token\",\"data\":null}");
            httpStatusToReturn.set(401);

            OfflineHelperCore.ApiResult resHttpError = OfflineHelperCore.submitOfflineDownload(
                    "http://127.0.0.1:" + port,
                    "bad_token",
                    urls,
                    "/115/影视/",
                    "115 Open",
                    "delete_on_upload_succeed",
                    5000
            );

            assertTrue(!resHttpError.success, "HTTP 401 result success must be false");
            assertEquals(401, resHttpError.code, "HTTP 401 code match");
            assertEquals("Invalid token", resHttpError.message, "HTTP 401 message match");

        } finally {
            server.stop(0);
        }
    }

    private static void testConfigBasedPayloadAndSubmit() throws IOException {
        OfflineHelperCore.OfflineConfig config = new OfflineHelperCore.OfflineConfig();
        config.host = "127.0.0.1";
        config.port = 5244;
        config.token = "token_from_config";
        config.path = "/115/电视剧/";
        config.tool = "115 Open";
        config.deletePolicy = "delete_on_upload_succeed";

        List<String> urls = Collections.singletonList("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567");

        String payload = OfflineHelperCore.buildRequestPayload(urls, config);
        assertTrue(payload.contains("\"path\":\"/115/电视剧/\""), "Config path used in buildRequestPayload");
        assertTrue(payload.contains("\"tool\":\"115 Open\""), "Config tool used in buildRequestPayload");

        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int testPort = server.getAddress().getPort();
        config.port = testPort;

        AtomicReference<String> receivedAuth = new AtomicReference<>("");
        AtomicReference<String> receivedBody = new AtomicReference<>("");

        server.createContext("/api/fs/add_offline_download", exchange -> {
            receivedAuth.set(exchange.getRequestHeaders().getFirst("Authorization"));
            try (InputStream is = exchange.getRequestBody();
                 ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                byte[] buf = new byte[1024];
                int len;
                while ((len = is.read(buf)) != -1) {
                    baos.write(buf, 0, len);
                }
                receivedBody.set(baos.toString(StandardCharsets.UTF_8.name()));
            }

            byte[] respBytes = "{\"code\":200,\"message\":\"success\",\"data\":null}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(200, respBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(respBytes);
                os.flush();
            }
        });

        server.start();
        try {
            OfflineHelperCore.ApiResult res = OfflineHelperCore.submitOfflineDownload(urls, config, 5000);
            assertTrue(res.success, "submitOfflineDownload with config should succeed");
            assertEquals("token_from_config", receivedAuth.get(), "Auth header matched from config");
            assertTrue(receivedBody.get().contains("/115/电视剧/"), "Request body matched path from config");
        } finally {
            server.stop(0);
        }
    }

    private static void testTokenSanitization() {
        // 1. openlist token with string suffix > 80 chars
        String longOpenListToken = "openlist-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4iLCJleHAiOjE3NjM1NjM4OTN9.someLongSignatureDataHereXYZ1234567890string";
        assertTrue(longOpenListToken.length() > 80, "Length > 80");
        String sanitized = OfflineHelperCore.sanitizeToken(longOpenListToken);
        assertEquals("openlist-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4iLCJleHAiOjE3NjM1NjM4OTN9.someLongSignatureDataHereXYZ1234567890", sanitized, "Suffix 'string' stripped");

        // 2. alist token with string suffix > 80 chars
        String longAListToken = "alist-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4iLCJleHAiOjE3NjM1NjM4OTN9.someLongSignatureDataHereXYZ1234567890string";
        String sanitizedAList = OfflineHelperCore.sanitizeToken(longAListToken);
        assertEquals("alist-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4iLCJleHAiOjE3NjM1NjM4OTN9.someLongSignatureDataHereXYZ1234567890", sanitizedAList, "AList suffix 'string' stripped");

        // 3. Normal token without string suffix
        String normalToken = "openlist-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.normalTokenWithoutSuffix";
        assertEquals(normalToken, OfflineHelperCore.sanitizeToken(normalToken), "Normal token without string suffix untouched");

        // 4. Short token ending in string (< 26 chars)
        String shortToken = "openlist-shortstring";
        assertEquals(shortToken, OfflineHelperCore.sanitizeToken(shortToken), "Short token < 26 untouched");

        // 4b. Token with length >= 26 ending in string is sanitized
        String pollutedToken27 = "alist-123456789012345string"; // 27 chars >= 26
        assertEquals("alist-123456789012345", OfflineHelperCore.sanitizeToken(pollutedToken27), "Token length >= 26 stripped");

        // 5. Token parsed from config string
        String confWithSuffix = "HOST=127.0.0.1\nPORT=5244\nTOKEN=" + longOpenListToken + "\n";
        OfflineHelperCore.OfflineConfig parsed = OfflineHelperCore.OfflineConfig.parse(confWithSuffix);
        assertEquals("openlist-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiYWRtaW4iLCJleHAiOjE3NjM1NjM4OTN9.someLongSignatureDataHereXYZ1234567890", parsed.token, "Parsed config token sanitized");
    }

    private static void testApiResultIsStorageError() {
        OfflineHelperCore.ApiResult successRes = new OfflineHelperCore.ApiResult(true, 200, "success", "{}");
        assertTrue(!successRes.isStorageError(), "Success result is not storage error");

        OfflineHelperCore.ApiResult storageInMsg = new OfflineHelperCore.ApiResult(false, 500, "storage not init", "");
        assertTrue(storageInMsg.isStorageError(), "Storage not init in message detected");

        OfflineHelperCore.ApiResult disabledInBody = new OfflineHelperCore.ApiResult(false, 500, "unknown error", "{\"error\":\"storage disabled\"}");
        assertTrue(disabledInBody.isStorageError(), "Storage disabled in body detected");

        OfflineHelperCore.ApiResult otherError = new OfflineHelperCore.ApiResult(false, 500, "timeout", "network timeout");
        assertTrue(!otherError.isStorageError(), "Other error is not storage error");
    }

    private static void testAutoHealStorageNotInit() throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int testPort = server.getAddress().getPort();

        AtomicInteger addOfflineCalls = new AtomicInteger(0);
        AtomicInteger loadAllCalls = new AtomicInteger(0);
        AtomicReference<String> loadAllAuth = new AtomicReference<>("");

        // /api/fs/add_offline_download: fails on 1st call with storage not init, succeeds on 2nd call
        server.createContext("/api/fs/add_offline_download", exchange -> {
            int callNum = addOfflineCalls.incrementAndGet();
            byte[] respBytes;
            int httpStatus;
            if (callNum == 1) {
                // First call: storage not init
                respBytes = "{\"code\":500,\"message\":\"storage not init: dial tcp: lookup proapi.115.com: no such host\",\"data\":null}".getBytes(StandardCharsets.UTF_8);
                httpStatus = 200;
            } else {
                // Second call: success
                respBytes = "{\"code\":200,\"message\":\"success\",\"data\":null}".getBytes(StandardCharsets.UTF_8);
                httpStatus = 200;
            }

            exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(httpStatus, respBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(respBytes);
                os.flush();
            }
        });

        // /api/admin/storage/load_all: records call and returns success
        server.createContext("/api/admin/storage/load_all", exchange -> {
            loadAllCalls.incrementAndGet();
            loadAllAuth.set(exchange.getRequestHeaders().getFirst("Authorization"));
            byte[] respBytes = "{\"code\":200,\"message\":\"success\",\"data\":null}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(200, respBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(respBytes);
                os.flush();
            }
        });

        server.start();

        try {
            List<String> urls = Collections.singletonList("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567");
            String testToken = "openlist-token-test-123456789012345678901234567890123456789012345678901234567890string";

            OfflineHelperCore.ApiResult res = OfflineHelperCore.submitOfflineDownload(
                    "http://127.0.0.1:" + testPort,
                    testToken,
                    urls,
                    "/115/影视/",
                    "115 Open",
                    "delete_on_upload_succeed",
                    5000
            );

            // Verifications
            assertEquals(2, addOfflineCalls.get(), "add_offline_download called twice (initial + retry)");
            assertEquals(1, loadAllCalls.get(), "/api/admin/storage/load_all called exactly once");
            // Also verifies token sanitization in Authorization header sent to load_all
            assertEquals("openlist-token-test-123456789012345678901234567890123456789012345678901234567890", loadAllAuth.get(), "Sanitized token sent to /api/admin/storage/load_all");
            assertTrue(res.success, "Auto-healed submitOfflineDownload should succeed");
            assertEquals(200, res.code, "Final result code is 200");
            assertEquals("success", res.message, "Final result message is success");
        } finally {
            server.stop(0);
        }
    }

    private static void testManifestDefaultDisabledProcessTextActivity() throws IOException {
        File manifestFile = new File("companion-apk/AndroidManifest.xml");
        if (!manifestFile.exists()) {
            manifestFile = new File("AndroidManifest.xml");
        }
        assertTrue(manifestFile.exists(), "companion-apk/AndroidManifest.xml must exist");

        String content = new String(Files.readAllBytes(manifestFile.toPath()), StandardCharsets.UTF_8);

        int activityStart = content.indexOf("<activity");
        assertTrue(activityStart >= 0, "Manifest must declare <activity>");
        int activityTagEnd = content.indexOf(">", activityStart);
        assertTrue(activityTagEnd > activityStart, "<activity> opening tag must close with >");
        int activityClose = content.indexOf("</activity>", activityTagEnd);
        assertTrue(activityClose > activityTagEnd, "<activity> must have closing </activity>");

        String activityOpeningTag = content.substring(activityStart, activityTagEnd + 1);
        String activityBody = content.substring(activityStart, activityClose + "</activity>".length());

        assertTrue(activityOpeningTag.contains("android:name=\".ProcessTextActivity\""),
                "<activity> must declare android:name=\".ProcessTextActivity\"");
        assertTrue(activityOpeningTag.contains("android:enabled=\"false\""),
                "ProcessTextActivity must declare android:enabled=\"false\" by default");

        assertTrue(activityBody.contains("android.intent.action.PROCESS_TEXT"),
                "ProcessTextActivity must retain android.intent.action.PROCESS_TEXT");
        assertTrue(activityBody.contains("android.intent.action.SEND"),
                "ProcessTextActivity must retain android.intent.action.SEND");
        assertTrue(activityBody.contains("android.intent.action.VIEW"),
                "ProcessTextActivity must retain android.intent.action.VIEW");
    }

    private static void testVirtualPathHelpers() {
        // 1. normalizeVirtualPath
        assertEquals("/", OfflineHelperCore.normalizeVirtualPath(null), "Null path -> /");
        assertEquals("/", OfflineHelperCore.normalizeVirtualPath(""), "Empty path -> /");
        assertEquals("/", OfflineHelperCore.normalizeVirtualPath("   "), "Whitespace path -> /");
        assertEquals("/", OfflineHelperCore.normalizeVirtualPath("/"), "Root / -> /");
        assertEquals("/", OfflineHelperCore.normalizeVirtualPath("///"), "Multiple root slashes -> /");
        assertEquals("/115/", OfflineHelperCore.normalizeVirtualPath("/115"), "No trailing slash -> /115/");
        assertEquals("/115/", OfflineHelperCore.normalizeVirtualPath("/115/"), "With trailing slash -> /115/");
        assertEquals("/115/影视/", OfflineHelperCore.normalizeVirtualPath("/115/影视"), "/115/影视 -> /115/影视/");
        assertEquals("/115/影视/", OfflineHelperCore.normalizeVirtualPath("/115/影视/"), "/115/影视/ -> /115/影视/");
        assertEquals("/115/动漫/", OfflineHelperCore.normalizeVirtualPath("115/动漫"), "Leading slash added");
        assertEquals("/115/动漫/", OfflineHelperCore.normalizeVirtualPath("115\\动漫\\"), "Backslash replaced");
        assertEquals("/115/影视/", OfflineHelperCore.normalizeVirtualPath("//115///影视//"), "Consecutive slashes collapsed");
        assertEquals("/115/影视/", OfflineHelperCore.normalizeVirtualPath("   /115/影视   "), "Padded whitespace trimmed");

        // 2. parentVirtualPath
        assertEquals("/", OfflineHelperCore.parentVirtualPath("/"), "Parent of / -> /");
        assertEquals("/", OfflineHelperCore.parentVirtualPath(null), "Parent of null -> /");
        assertEquals("/", OfflineHelperCore.parentVirtualPath(""), "Parent of empty -> /");
        assertEquals("/", OfflineHelperCore.parentVirtualPath("/115"), "Parent of /115 -> /");
        assertEquals("/", OfflineHelperCore.parentVirtualPath("/115/"), "Parent of /115/ -> /");
        assertEquals("/115/", OfflineHelperCore.parentVirtualPath("/115/影视"), "Parent of /115/影视 -> /115/");
        assertEquals("/115/", OfflineHelperCore.parentVirtualPath("/115/影视/"), "Parent of /115/影视/ -> /115/");
        assertEquals("/115/", OfflineHelperCore.parentVirtualPath("115/动漫"), "Parent of 115/动漫 -> /115/");
        assertEquals("/115/影视/", OfflineHelperCore.parentVirtualPath("/115/影视/子目录/"), "Parent of multi-level -> /115/影视/");

        // 3. joinVirtualPath
        assertEquals("/115/影视/", OfflineHelperCore.joinVirtualPath("/115/", "影视"), "Join /115/ and 影视 -> /115/影视/");
        assertEquals("/115/影视/", OfflineHelperCore.joinVirtualPath("/115", "影视"), "Join /115 and 影视 -> /115/影视/");
        assertEquals("/115/", OfflineHelperCore.joinVirtualPath("/", "115"), "Join / and 115 -> /115/");
        assertEquals("/115/影视/", OfflineHelperCore.joinVirtualPath("/115/", "/影视/"), "Join handles internal slashes");
        assertEquals("/115/影视/科幻/", OfflineHelperCore.joinVirtualPath("/115/影视/", "科幻"), "Join subfolder -> /115/影视/科幻/");
        assertEquals("/115/", OfflineHelperCore.joinVirtualPath("/115/", null), "Join with null child preserves parent");
        assertEquals("/115/", OfflineHelperCore.joinVirtualPath("/115/", "   "), "Join with empty child preserves parent");
        assertEquals("/115/", OfflineHelperCore.joinVirtualPath(null, "115"), "Join with null parent uses root");

        // 4. buildListDirectoryPayload
        assertEquals("{\"path\":\"/\",\"password\":\"\",\"page\":1,\"per_page\":0,\"refresh\":false}",
                OfflineHelperCore.buildListDirectoryPayload("/"), "Payload for root /");
        assertEquals("{\"path\":\"/115/影视\",\"password\":\"\",\"page\":1,\"per_page\":0,\"refresh\":false}",
                OfflineHelperCore.buildListDirectoryPayload("/115/影视/"), "Payload for /115/影视/ strips trailing slash");
        assertEquals("{\"path\":\"/115\",\"password\":\"\",\"page\":1,\"per_page\":0,\"refresh\":false}",
                OfflineHelperCore.buildListDirectoryPayload("/115"), "Payload for /115");
        assertTrue(OfflineHelperCore.buildListDirectoryPayload("/115/特殊\"名/").contains("\\\""),
                "Payload properly escapes quotes in path");
    }

    private static void testParseDirectoryNamesFromListJson() {
        String json = "{\n" +
                "  \"code\": 200,\n" +
                "  \"message\": \"success\",\n" +
                "  \"data\": {\n" +
                "    \"content\": [\n" +
                "      {\"name\": \"云下载\", \"size\": 0, \"is_dir\": true, \"modified\": \"2024-01-01T00:00:00Z\"},\n" +
                "      {\"name\": \"影视\", \"size\": 0, \"is_dir\": true, \"modified\": \"2024-01-01T00:00:00Z\"},\n" +
                "      {\"name\": \"movie.mkv\", \"size\": 1048576, \"is_dir\": false, \"modified\": \"2024-01-01T00:00:00Z\"},\n" +
                "      {\"name\": \"Special \\\"Folder\\\" \\\\ Path\", \"size\": 0, \"is_dir\": true, \"modified\": \"2024-01-01T00:00:00Z\"},\n" +
                "      {\"name\": \"README.txt\", \"size\": 256, \"is_dir\": false, \"modified\": \"2024-01-01T00:00:00Z\"},\n" +
                "      {\"name\": \"云下载\", \"size\": 0, \"is_dir\": true, \"modified\": \"2024-01-01T00:00:00Z\"}\n" +
                "    ],\n" +
                "    \"total\": 6,\n" +
                "    \"readme\": \"\",\n" +
                "    \"write\": true,\n" +
                "    \"provider\": \"115 Open\"\n" +
                "  }\n" +
                "}";

        List<String> dirs = OfflineHelperCore.parseDirectoryNamesFromListJson(json);
        assertEquals(3, dirs.size(), "Should extract 3 unique directories");
        assertEquals("云下载", dirs.get(0), "Dir 0");
        assertEquals("影视", dirs.get(1), "Dir 1");
        assertEquals("Special \"Folder\" \\ Path", dirs.get(2), "Dir 2 with unescaped quotes and slashes");

        // Unicode escaped name
        String unicodeJson = "{\"code\":200,\"data\":{\"content\":[{\"name\":\"\\u4e91\\u4e0b\\u8f7d\",\"is_dir\":true}]}}";
        List<String> unicodeDirs = OfflineHelperCore.parseDirectoryNamesFromListJson(unicodeJson);
        assertEquals(1, unicodeDirs.size(), "Unicode dir extracted");
        assertEquals("云下载", unicodeDirs.get(0), "Unicode decoded correctly");

        // Reversed key order and nested objects
        String reversedJson = "{\"code\":200,\"data\":{\"content\":[{\"is_dir\":true,\"extra\":{\"a\":1},\"name\":\"反序目录\"}]}}";
        List<String> reversedDirs = OfflineHelperCore.parseDirectoryNamesFromListJson(reversedJson);
        assertEquals(1, reversedDirs.size(), "Reversed key order with nested object");
        assertEquals("反序目录", reversedDirs.get(0), "Extracted name with reversed keys");

        // Empty content or null content
        assertEquals(0, OfflineHelperCore.parseDirectoryNamesFromListJson(null).size(), "Null json -> empty");
        assertEquals(0, OfflineHelperCore.parseDirectoryNamesFromListJson("").size(), "Empty json -> empty");
        assertEquals(0, OfflineHelperCore.parseDirectoryNamesFromListJson("{\"code\":200,\"data\":{\"content\":null}}").size(), "Null content -> empty");
        assertEquals(0, OfflineHelperCore.parseDirectoryNamesFromListJson("{\"code\":200,\"data\":{\"content\":[]}}").size(), "Empty content -> empty");
        assertEquals(0, OfflineHelperCore.parseDirectoryNamesFromListJson("{\"code\":200,\"data\":null}").size(), "Null data -> empty");

        // DirListResult isStorageError unit verification
        OfflineHelperCore.DirListResult successResult = new OfflineHelperCore.DirListResult(true, 200, "storage not init", "/", Collections.emptyList(), "");
        assertTrue(!successResult.isStorageError(), "Success DirListResult is never a storage error");

        OfflineHelperCore.DirListResult storageInMsgResult = new OfflineHelperCore.DirListResult(false, 500, "storage not init", "/", Collections.emptyList(), "");
        assertTrue(storageInMsgResult.isStorageError(), "Storage not init in message is detected");

        OfflineHelperCore.DirListResult disabledInBodyResult = new OfflineHelperCore.DirListResult(false, 500, "fail", "/", Collections.emptyList(), "{\"error\":\"storage disabled\"}");
        assertTrue(disabledInBodyResult.isStorageError(), "Storage disabled in body is detected");

        OfflineHelperCore.DirListResult unauthResult = new OfflineHelperCore.DirListResult(false, 401, "unauthorized", "/", Collections.emptyList(), "{\"code\":401}");
        assertTrue(!unauthResult.isStorageError(), "Unauthorized is not a storage error");
    }

    private static void testListDirectoriesMockHttpAndAutoHeal() throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int testPort = server.getAddress().getPort();

        AtomicInteger listCalls = new AtomicInteger(0);
        AtomicInteger loadAllCalls = new AtomicInteger(0);
        AtomicReference<String> listAuth = new AtomicReference<>("");
        AtomicReference<String> listBody = new AtomicReference<>("");

        server.createContext("/api/fs/list", exchange -> {
            int callNum = listCalls.incrementAndGet();
            listAuth.set(exchange.getRequestHeaders().getFirst("Authorization"));
            try (InputStream is = exchange.getRequestBody();
                 ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
                byte[] buf = new byte[1024];
                int len;
                while ((len = is.read(buf)) != -1) {
                    baos.write(buf, 0, len);
                }
                listBody.set(baos.toString(StandardCharsets.UTF_8.name()));
            }

            byte[] respBytes;
            if (callNum == 1) {
                // First call: fail with storage not init
                respBytes = "{\"code\":500,\"message\":\"storage not init: dial tcp lookup 115 error\",\"data\":null}".getBytes(StandardCharsets.UTF_8);
            } else {
                // Subsequent calls: success with 2 folders and 1 file
                respBytes = ("{\n" +
                        "  \"code\": 200,\n" +
                        "  \"message\": \"success\",\n" +
                        "  \"data\": {\n" +
                        "    \"content\": [\n" +
                        "      {\"name\": \"影视\", \"is_dir\": true},\n" +
                        "      {\"name\": \"动漫\", \"is_dir\": true},\n" +
                        "      {\"name\": \"notes.txt\", \"is_dir\": false}\n" +
                        "    ]\n" +
                        "  }\n" +
                        "}").getBytes(StandardCharsets.UTF_8);
            }

            exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(200, respBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(respBytes);
                os.flush();
            }
        });

        server.createContext("/api/admin/storage/load_all", exchange -> {
            loadAllCalls.incrementAndGet();
            byte[] respBytes = "{\"code\":200,\"message\":\"success\",\"data\":null}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
            exchange.sendResponseHeaders(200, respBytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(respBytes);
                os.flush();
            }
        });

        server.start();

        try {
            String baseUrl = "http://127.0.0.1:" + testPort;
            String token = "openlist-sample-token-123456789012345678901234567890string";

            // 1. Auto-heal test on first listDirectories call (call 1 fails, triggers load_all, call 2 succeeds)
            OfflineHelperCore.DirListResult res = OfflineHelperCore.listDirectories(baseUrl, token, "/115", 5000);

            assertTrue(res.success, "Auto-healed listDirectories must succeed");
            assertEquals(200, res.code, "Code 200");
            assertEquals("success", res.message, "Message success");
            assertEquals("/115/", res.currentPath, "Current path normalized to /115/");
            assertEquals(2, res.directories.size(), "Should have 2 directories");
            assertEquals("影视", res.directories.get(0), "First dir is 影视");
            assertEquals("动漫", res.directories.get(1), "Second dir is 动漫");
            assertEquals(2, listCalls.get(), "list called twice due to auto-heal");
            assertEquals(1, loadAllCalls.get(), "load_all called once");
            // Check that token was sanitized before sending
            assertEquals("openlist-sample-token-123456789012345678901234567890", listAuth.get(), "Sanitized token in Authorization");
            assertTrue(listBody.get().contains("\"path\":\"/115\""), "Request payload path is /115 without trailing slash");

            // 2. Config-based listDirectories call (now succeeds on first attempt)
            OfflineHelperCore.OfflineConfig config = new OfflineHelperCore.OfflineConfig();
            config.host = "127.0.0.1";
            config.port = testPort;
            config.token = "config-token-123";
            OfflineHelperCore.DirListResult configRes = OfflineHelperCore.listDirectories("/", config, 5000);
            assertTrue(configRes.success, "Config-based listDirectories succeeds");
            assertEquals("/", configRes.currentPath, "Root path is /");
            assertEquals(2, configRes.directories.size(), "Root dirs count");
        } finally {
            server.stop(0);
        }
    }
}
