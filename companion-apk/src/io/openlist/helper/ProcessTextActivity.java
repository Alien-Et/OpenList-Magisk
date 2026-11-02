package io.openlist.helper;

import android.app.Activity;
import android.app.Dialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;

public class ProcessTextActivity extends Activity {

    private Dialog currentDialog;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String incomingText = extractIncomingText();
        OfflineHelperCore.OfflineConfig config = loadEffectiveConfig();

        showOfflineConfirmSheet(incomingText, config);
    }

    private String extractIncomingText() {
        Intent intent = getIntent();
        if (intent == null) return "";

        CharSequence processText = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT);
        if (processText != null && processText.length() > 0) {
            return processText.toString().trim();
        }

        CharSequence extraText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
        if (extraText != null && extraText.length() > 0) {
            return extraText.toString().trim();
        }

        String dataString = intent.getDataString();
        if (dataString != null && !dataString.isEmpty()) {
            return dataString.trim();
        }

        return "";
    }

    private OfflineHelperCore.OfflineConfig loadEffectiveConfig() {
        // 1. Check bridge config from app files dir first, then fallback to /data/local/tmp/openlist_offline.conf
        OfflineHelperCore.OfflineConfig bridgeConfig = null;
        File appBridgeFile = new File(getFilesDir(), "offline.conf");
        if (appBridgeFile.exists() && appBridgeFile.canRead()) {
            bridgeConfig = OfflineHelperCore.OfflineConfig.parse(readFileContent(appBridgeFile));
        }

        if (bridgeConfig == null || bridgeConfig.token.isEmpty()) {
            File tmpBridgeFile = new File("/data/local/tmp/openlist_offline.conf");
            if (tmpBridgeFile.exists() && tmpBridgeFile.canRead()) {
                OfflineHelperCore.OfflineConfig tmpCfg = OfflineHelperCore.OfflineConfig.parse(readFileContent(tmpBridgeFile));
                bridgeConfig = (bridgeConfig == null) ? tmpCfg : OfflineHelperCore.OfflineConfig.mergeWithBridge(tmpCfg, bridgeConfig);
            }
        }

        // 2. Read user saved config
        File userConfFile = new File(getFilesDir(), "user_offline.conf");
        OfflineHelperCore.OfflineConfig userConfig = null;
        if (userConfFile.exists() && userConfFile.canRead()) {
            userConfig = OfflineHelperCore.OfflineConfig.parse(readFileContent(userConfFile));
        }

        // 3. Merge configurations
        return OfflineHelperCore.OfflineConfig.mergeWithBridge(bridgeConfig, userConfig);
    }

    private void showOfflineConfirmSheet(String incomingText, OfflineHelperCore.OfflineConfig config) {
        List<String> extractedUrls = OfflineHelperCore.extractMagnetUrls(incomingText);

        currentDialog = new Dialog(this);
        currentDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        Window window = currentDialog.getWindow();
        if (window != null) {
            window.setGravity(Gravity.BOTTOM);
            window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT);
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.setWindowAnimations(android.R.style.Animation_InputMethod);
        }

        currentDialog.setCanceledOnTouchOutside(true);
        currentDialog.setOnDismissListener(d -> {
            if (!isFinishing()) {
                finish();
            }
        });

        // Outer ScrollView to accommodate keyboards / small screens
        ScrollView outerScroll = new ScrollView(this);
        outerScroll.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        outerScroll.setFillViewport(true);

        // Root container with rounded top corners
        LinearLayout rootLayout = new LinearLayout(this);
        rootLayout.setOrientation(LinearLayout.VERTICAL);
        rootLayout.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        rootLayout.setPadding(dpToPx(20), dpToPx(12), dpToPx(20), dpToPx(24));

        GradientDrawable cardBg = new GradientDrawable();
        cardBg.setColor(Color.WHITE);
        float r = dpToPx(20);
        cardBg.setCornerRadii(new float[]{r, r, r, r, 0, 0, 0, 0});
        rootLayout.setBackground(cardBg);

        // Top drag handle
        View handleBar = new View(this);
        LinearLayout.LayoutParams handleParams = new LinearLayout.LayoutParams(dpToPx(40), dpToPx(4));
        handleParams.gravity = Gravity.CENTER_HORIZONTAL;
        handleParams.bottomMargin = dpToPx(12);
        handleBar.setLayoutParams(handleParams);
        GradientDrawable handleBg = new GradientDrawable();
        handleBg.setColor(Color.parseColor("#D1D5DB"));
        handleBg.setCornerRadius(dpToPx(2));
        handleBar.setBackground(handleBg);
        rootLayout.addView(handleBar);

        // Title Header
        TextView titleView = new TextView(this);
        titleView.setText("115 离线下载 (115 Open)");
        titleView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setTextColor(Color.parseColor("#111827"));
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.bottomMargin = dpToPx(12);
        titleView.setLayoutParams(titleParams);
        rootLayout.addView(titleView);

        // Magnet URLs label
        TextView urlLabel = new TextView(this);
        int urlCount = extractedUrls.size();
        urlLabel.setText(urlCount > 0 ? "磁力链接 (已解析 " + urlCount + " 条):" : "磁力链接 / InfoHash:");
        urlLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        urlLabel.setTextColor(Color.parseColor("#4B5563"));
        urlLabel.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams labelParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        labelParams.bottomMargin = dpToPx(6);
        urlLabel.setLayoutParams(labelParams);
        rootLayout.addView(urlLabel);

        // Magnet URLs input / preview
        EditText urlEditText = new EditText(this);
        urlEditText.setMinLines(3);
        urlEditText.setMaxLines(5);
        urlEditText.setGravity(Gravity.TOP | Gravity.START);
        urlEditText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        urlEditText.setTextColor(Color.parseColor("#1F2937"));
        urlEditText.setPadding(dpToPx(10), dpToPx(10), dpToPx(10), dpToPx(10));
        urlEditText.setHint("未检测到标准磁力头，可确认或粘贴磁力/Hash");
        urlEditText.setHintTextColor(Color.parseColor("#9CA3AF"));

        GradientDrawable inputBg = new GradientDrawable();
        inputBg.setColor(Color.parseColor("#F9FAFB"));
        inputBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
        inputBg.setCornerRadius(dpToPx(8));
        urlEditText.setBackground(inputBg);

        if (!extractedUrls.isEmpty()) {
            urlEditText.setText(String.join("\n", extractedUrls));
        } else if (!incomingText.isEmpty()) {
            urlEditText.setText(incomingText);
        }

        LinearLayout.LayoutParams urlEditParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        urlEditParams.bottomMargin = dpToPx(14);
        urlEditText.setLayoutParams(urlEditParams);
        rootLayout.addView(urlEditText);

        // Target path label
        TextView pathLabel = new TextView(this);
        pathLabel.setText("目标虚拟路径:");
        pathLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        pathLabel.setTextColor(Color.parseColor("#4B5563"));
        pathLabel.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams pathLabelParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        pathLabelParams.bottomMargin = dpToPx(6);
        pathLabel.setLayoutParams(pathLabelParams);
        rootLayout.addView(pathLabel);

        // Target path EditText pre-filled with config.path (default "/115/影视/")
        EditText pathEditText = new EditText(this);
        pathEditText.setSingleLine(true);
        pathEditText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        pathEditText.setTextColor(Color.parseColor("#1F2937"));
        pathEditText.setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8));
        pathEditText.setText(config.path != null && !config.path.isEmpty() ? config.path : "/115/影视/");

        GradientDrawable pathEditBg = new GradientDrawable();
        pathEditBg.setColor(Color.parseColor("#F9FAFB"));
        pathEditBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
        pathEditBg.setCornerRadius(dpToPx(8));
        pathEditText.setBackground(pathEditBg);

        LinearLayout.LayoutParams pathEditParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        pathEditParams.bottomMargin = dpToPx(12);
        pathEditText.setLayoutParams(pathEditParams);
        rootLayout.addView(pathEditText);

        // Token warning if token is empty
        if (config.token == null || config.token.trim().isEmpty()) {
            TextView tokenWarning = new TextView(this);
            tokenWarning.setText("⚠️ 未检测到 OpenList Token，请检查 data/offline.conf 或重启服务");
            tokenWarning.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            tokenWarning.setTextColor(Color.parseColor("#DC2626"));
            tokenWarning.setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8));

            GradientDrawable warnBg = new GradientDrawable();
            warnBg.setColor(Color.parseColor("#FEF2F2"));
            warnBg.setStroke(dpToPx(1), Color.parseColor("#FECACA"));
            warnBg.setCornerRadius(dpToPx(6));
            tokenWarning.setBackground(warnBg);

            LinearLayout.LayoutParams warnParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            warnParams.bottomMargin = dpToPx(14);
            tokenWarning.setLayoutParams(warnParams);
            rootLayout.addView(tokenWarning);
        }

        // Bottom Action Buttons
        LinearLayout buttonRow = new LinearLayout(this);
        buttonRow.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams btnRowParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        btnRowParams.topMargin = dpToPx(8);
        buttonRow.setLayoutParams(btnRowParams);

        // Cancel Button
        Button cancelBtn = new Button(this);
        cancelBtn.setText("取消");
        cancelBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        cancelBtn.setTextColor(Color.parseColor("#4B5563"));
        cancelBtn.setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10));
        GradientDrawable cancelBg = new GradientDrawable();
        cancelBg.setColor(Color.parseColor("#F3F4F6"));
        cancelBg.setCornerRadius(dpToPx(8));
        cancelBtn.setBackground(cancelBg);
        LinearLayout.LayoutParams cancelParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        cancelParams.rightMargin = dpToPx(8);
        cancelBtn.setLayoutParams(cancelParams);
        cancelBtn.setOnClickListener(v -> {
            currentDialog.dismiss();
            finish();
        });
        buttonRow.addView(cancelBtn);

        // Submit Button
        Button submitBtn = new Button(this);
        submitBtn.setText("立即离线");
        submitBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        submitBtn.setTypeface(Typeface.DEFAULT_BOLD);
        submitBtn.setTextColor(Color.WHITE);
        submitBtn.setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10));
        GradientDrawable submitBg = new GradientDrawable();
        submitBg.setColor(Color.parseColor("#2563EB"));
        submitBg.setCornerRadius(dpToPx(8));
        submitBtn.setBackground(submitBg);
        LinearLayout.LayoutParams submitParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.5f);
        submitParams.leftMargin = dpToPx(8);
        submitBtn.setLayoutParams(submitParams);

        submitBtn.setOnClickListener(v -> {
            String rawContent = urlEditText.getText().toString().trim();
            List<String> targetUrls = OfflineHelperCore.extractMagnetUrls(rawContent);
            if (targetUrls.isEmpty()) {
                Toast.makeText(ProcessTextActivity.this, "❌ 未检测到有效磁力链接或 Hash", Toast.LENGTH_SHORT).show();
                return;
            }

            String targetPath = pathEditText.getText().toString().trim();
            if (targetPath.isEmpty()) {
                targetPath = "/115/影视/";
            }

            // Persist confirmed path to user_offline.conf so user's chosen directory is remembered next time
            config.path = targetPath;
            saveUserConfig(config);

            submitBtn.setEnabled(false);
            submitBtn.setText("正在提交...");

            final String finalTargetPath = targetPath;
            new Thread(() -> {
                OfflineHelperCore.ApiResult res = OfflineHelperCore.submitOfflineDownload(
                        targetUrls, config, 15000
                );

                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;

                    if (res.success) {
                        Toast.makeText(ProcessTextActivity.this, "✅ 已添加 115 离线任务 -> " + finalTargetPath, Toast.LENGTH_LONG).show();
                        if (currentDialog != null && currentDialog.isShowing()) {
                            currentDialog.dismiss();
                        }
                        finish();
                    } else {
                        submitBtn.setEnabled(true);
                        submitBtn.setText("立即离线");
                        String errMsg = (res.message != null && !res.message.isEmpty()) ? res.message : ("HTTP " + res.code);
                        Toast.makeText(ProcessTextActivity.this, "❌ 离线失败: " + errMsg, Toast.LENGTH_LONG).show();
                    }
                });
            }).start();
        });
        buttonRow.addView(submitBtn);

        rootLayout.addView(buttonRow);
        outerScroll.addView(rootLayout);

        currentDialog.setContentView(outerScroll);
        currentDialog.show();
    }

    private void saveUserConfig(OfflineHelperCore.OfflineConfig config) {
        try {
            File userConfFile = new File(getFilesDir(), "user_offline.conf");
            writeFileContent(userConfFile, config.serialize());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private String readFileContent(File file) {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append("\n");
            }
        } catch (Exception ignored) {}
        return sb.toString();
    }

    private void writeFileContent(File file, String content) {
        try {
            File parent = file.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            try (FileOutputStream fos = new FileOutputStream(file)) {
                fos.write(content.getBytes(StandardCharsets.UTF_8));
                fos.flush();
            }
        } catch (Exception ignored) {}
    }

    private int dpToPx(float dpValue) {
        return (int) (dpValue * getResources().getDisplayMetrics().density + 0.5f);
    }

    @Override
    protected void onDestroy() {
        if (currentDialog != null && currentDialog.isShowing()) {
            currentDialog.dismiss();
        }
        super.onDestroy();
    }
}
