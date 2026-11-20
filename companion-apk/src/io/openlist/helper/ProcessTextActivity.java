package io.openlist.helper;

import android.app.Activity;
import android.app.Dialog;
import android.content.ClipData;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.HorizontalScrollView;
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
import java.util.ArrayList;
import java.util.List;

public class ProcessTextActivity extends Activity {

    private Dialog currentDialog;
    private Dialog pickerDialog;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String incomingText = extractIncomingText(getIntent());
        OfflineHelperCore.OfflineConfig config = loadEffectiveConfig();

        showOfflineConfirmSheet(incomingText, config);
    }

    public static String extractIncomingText(Intent intent) {
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

        ClipData clipData = intent.getClipData();
        if (clipData != null && clipData.getItemCount() > 0) {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < clipData.getItemCount(); i++) {
                ClipData.Item item = clipData.getItemAt(i);
                if (item != null) {
                    CharSequence itemText = item.getText();
                    if (itemText != null && itemText.length() > 0) {
                        String s = itemText.toString().trim();
                        if (!s.isEmpty()) {
                            if (sb.length() > 0) sb.append("\n");
                            sb.append(s);
                        }
                    }
                    if (item.getUri() != null) {
                        String uriStr = item.getUri().toString();
                        if (uriStr != null && !uriStr.trim().isEmpty()) {
                            if (sb.length() > 0) sb.append("\n");
                            sb.append(uriStr.trim());
                        }
                    }
                }
            }
            if (sb.length() > 0) {
                return sb.toString();
            }
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

        // Target path input row (pathEditText + "📁 选择目录" Button)
        LinearLayout pathRow = new LinearLayout(this);
        pathRow.setOrientation(LinearLayout.HORIZONTAL);
        pathRow.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams pathRowParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        pathRowParams.bottomMargin = dpToPx(8);
        pathRow.setLayoutParams(pathRowParams);

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

        LinearLayout.LayoutParams pathEditParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        pathEditText.setLayoutParams(pathEditParams);
        pathRow.addView(pathEditText);

        // Preset chips container
        LinearLayout presetContainer = new LinearLayout(this);
        presetContainer.setOrientation(LinearLayout.HORIZONTAL);
        presetContainer.setGravity(Gravity.CENTER_VERTICAL);

        // "📁 选择目录" Button
        Button pickDirBtn = new Button(this);
        pickDirBtn.setText("📁 选择目录");
        pickDirBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        pickDirBtn.setTextColor(Color.parseColor("#1D4ED8"));
        pickDirBtn.setPadding(dpToPx(10), dpToPx(8), dpToPx(10), dpToPx(8));
        GradientDrawable pickDirBg = new GradientDrawable();
        pickDirBg.setColor(Color.parseColor("#EFF6FF"));
        pickDirBg.setStroke(dpToPx(1), Color.parseColor("#BFDBFE"));
        pickDirBg.setCornerRadius(dpToPx(8));
        pickDirBtn.setBackground(pickDirBg);
        LinearLayout.LayoutParams pickDirParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        pickDirParams.leftMargin = dpToPx(8);
        pickDirBtn.setLayoutParams(pickDirParams);
        pickDirBtn.setOnClickListener(v -> {
            showDirectoryPickerDialog(pathEditText.getText().toString(), config, pathEditText, presetContainer);
        });
        pathRow.addView(pickDirBtn);

        rootLayout.addView(pathRow);

        // Preset path chips scroll view
        HorizontalScrollView presetScrollView = new HorizontalScrollView(this);
        presetScrollView.setHorizontalScrollBarEnabled(false);
        LinearLayout.LayoutParams presetScrollParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        presetScrollParams.bottomMargin = dpToPx(12);
        presetScrollView.setLayoutParams(presetScrollParams);

        renderPresetChips(presetContainer, config, pathEditText);
        presetScrollView.addView(presetContainer);
        rootLayout.addView(presetScrollView);

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
            targetPath = OfflineHelperCore.normalizeVirtualPath(targetPath);

            // Persist confirmed path to user_offline.conf so user's chosen directory is remembered next time
            config.path = targetPath;
            if (config.presetPaths == null) {
                config.presetPaths = new ArrayList<>();
            }
            if (!config.presetPaths.contains(targetPath)) {
                config.presetPaths.add(0, targetPath);
            }
            saveUserConfig(config);
            renderPresetChips(presetContainer, config, pathEditText);

            submitBtn.setEnabled(false);
            submitBtn.setText("正在提交...");

            final String finalTargetPath = targetPath;
            new Thread(() -> {
                OfflineHelperCore.ApiResult res = OfflineHelperCore.submitOfflineDownload(
                        targetUrls, config, 15000
                );

                if (res.success) {
                    new Thread(() -> {
                        try {
                            Thread.sleep(1500);
                        } catch (InterruptedException ignored) {
                        }
                        OfflineHelperCore.refreshDirectoryCache(finalTargetPath, config, 10000);
                    }).start();
                }

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

    private void renderPresetChips(LinearLayout container, OfflineHelperCore.OfflineConfig config, EditText pathEditText) {
        container.removeAllViews();
        if (config == null || config.presetPaths == null || config.presetPaths.isEmpty()) {
            return;
        }
        for (String preset : config.presetPaths) {
            if (preset == null || preset.trim().isEmpty()) continue;
            final String finalPreset = preset.trim();

            TextView chip = new TextView(this);
            chip.setText(finalPreset);
            chip.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            chip.setTextColor(Color.parseColor("#1D4ED8"));
            chip.setPadding(dpToPx(10), dpToPx(5), dpToPx(10), dpToPx(5));

            GradientDrawable chipBg = new GradientDrawable();
            chipBg.setColor(Color.parseColor("#EFF6FF"));
            chipBg.setStroke(dpToPx(1), Color.parseColor("#BFDBFE"));
            chipBg.setCornerRadius(dpToPx(14));
            chip.setBackground(chipBg);

            LinearLayout.LayoutParams chipParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            chipParams.rightMargin = dpToPx(6);
            chip.setLayoutParams(chipParams);

            chip.setOnClickListener(v -> {
                pathEditText.setText(finalPreset);
            });

            container.addView(chip);
        }
    }

    private void showDirectoryPickerDialog(
            String initialPath,
            OfflineHelperCore.OfflineConfig config,
            EditText targetPathEditText,
            LinearLayout presetContainer
    ) {
        if (pickerDialog != null && pickerDialog.isShowing()) {
            pickerDialog.dismiss();
        }

        pickerDialog = new Dialog(this);
        pickerDialog.requestWindowFeature(Window.FEATURE_NO_TITLE);

        Window window = pickerDialog.getWindow();
        if (window != null) {
            window.setGravity(Gravity.BOTTOM);
            window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT);
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.setWindowAnimations(android.R.style.Animation_InputMethod);
        }

        pickerDialog.setCanceledOnTouchOutside(true);
        pickerDialog.setOnDismissListener(d -> pickerDialog = null);

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

        // Header Title
        TextView titleView = new TextView(this);
        titleView.setText("选择保存文件夹");
        titleView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setTextColor(Color.parseColor("#111827"));
        LinearLayout.LayoutParams titleParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        titleParams.bottomMargin = dpToPx(8);
        titleView.setLayoutParams(titleParams);
        rootLayout.addView(titleView);

        // Current browsing path
        String startPath = (initialPath != null && !initialPath.trim().isEmpty()) ? initialPath.trim() : "/115/影视/";
        final String[] currentBrowsePath = new String[]{ OfflineHelperCore.normalizeVirtualPath(startPath) };

        TextView currentPathView = new TextView(this);
        currentPathView.setText("当前路径: " + currentBrowsePath[0]);
        currentPathView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        currentPathView.setTypeface(Typeface.DEFAULT_BOLD);
        currentPathView.setTextColor(Color.parseColor("#4B5563"));
        LinearLayout.LayoutParams curPathParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        curPathParams.bottomMargin = dpToPx(8);
        currentPathView.setLayoutParams(curPathParams);
        rootLayout.addView(currentPathView);

        // Navigation bar row
        LinearLayout navBar = new LinearLayout(this);
        navBar.setOrientation(LinearLayout.HORIZONTAL);
        navBar.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout.LayoutParams navBarParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        navBarParams.bottomMargin = dpToPx(8);
        navBar.setLayoutParams(navBarParams);

        // "⬆️ 上级目录" Button
        Button upBtn = new Button(this);
        upBtn.setText("⬆️ 上级目录");
        upBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        upBtn.setTextColor(Color.parseColor("#374151"));
        upBtn.setPadding(dpToPx(10), dpToPx(6), dpToPx(10), dpToPx(6));
        GradientDrawable upBg = new GradientDrawable();
        upBg.setColor(Color.parseColor("#F3F4F6"));
        upBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
        upBg.setCornerRadius(dpToPx(6));
        upBtn.setBackground(upBg);
        LinearLayout.LayoutParams upParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        upParams.rightMargin = dpToPx(8);
        upBtn.setLayoutParams(upParams);
        navBar.addView(upBtn);

        // "🏠 根目录 (/)" Button
        Button rootBtn = new Button(this);
        rootBtn.setText("🏠 根目录 (/)");
        rootBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        rootBtn.setTextColor(Color.parseColor("#374151"));
        rootBtn.setPadding(dpToPx(10), dpToPx(6), dpToPx(10), dpToPx(6));
        GradientDrawable rootBg = new GradientDrawable();
        rootBg.setColor(Color.parseColor("#F3F4F6"));
        rootBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
        rootBg.setCornerRadius(dpToPx(6));
        rootBtn.setBackground(rootBg);
        LinearLayout.LayoutParams rootParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        rootParams.rightMargin = dpToPx(8);
        rootBtn.setLayoutParams(rootParams);
        navBar.addView(rootBtn);

        // "🔄 刷新" Button
        Button refreshBtn = new Button(this);
        refreshBtn.setText("🔄 刷新");
        refreshBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        refreshBtn.setTextColor(Color.parseColor("#374151"));
        refreshBtn.setPadding(dpToPx(10), dpToPx(6), dpToPx(10), dpToPx(6));
        GradientDrawable refBg = new GradientDrawable();
        refBg.setColor(Color.parseColor("#F3F4F6"));
        refBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
        refBg.setCornerRadius(dpToPx(6));
        refreshBtn.setBackground(refBg);
        LinearLayout.LayoutParams refParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        refreshBtn.setLayoutParams(refParams);
        navBar.addView(refreshBtn);

        rootLayout.addView(navBar);

        // Scrollable Folder List
        ScrollView listScroll = new ScrollView(this);
        listScroll.setFillViewport(true);
        GradientDrawable listBg = new GradientDrawable();
        listBg.setColor(Color.parseColor("#F9FAFB"));
        listBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
        listBg.setCornerRadius(dpToPx(8));
        listScroll.setBackground(listBg);

        LinearLayout.LayoutParams scrollParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dpToPx(240));
        scrollParams.bottomMargin = dpToPx(12);
        listScroll.setLayoutParams(scrollParams);

        LinearLayout folderListLayout = new LinearLayout(this);
        folderListLayout.setOrientation(LinearLayout.VERTICAL);
        folderListLayout.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        folderListLayout.setPadding(dpToPx(8), dpToPx(8), dpToPx(8), dpToPx(8));
        listScroll.addView(folderListLayout);

        rootLayout.addView(listScroll);

        // Nav click listeners
        upBtn.setOnClickListener(v -> {
            loadDirectoryIntoPicker(OfflineHelperCore.parentVirtualPath(currentBrowsePath[0]), config, currentBrowsePath, currentPathView, upBtn, folderListLayout, false);
        });
        rootBtn.setOnClickListener(v -> {
            loadDirectoryIntoPicker("/", config, currentBrowsePath, currentPathView, upBtn, folderListLayout, false);
        });
        refreshBtn.setOnClickListener(v -> {
            loadDirectoryIntoPicker(currentBrowsePath[0], config, currentBrowsePath, currentPathView, upBtn, folderListLayout, true);
        });

        // Bottom button row
        LinearLayout bottomRow = new LinearLayout(this);
        bottomRow.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams bottomParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        bottomRow.setLayoutParams(bottomParams);

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
        cancelBtn.setOnClickListener(v -> pickerDialog.dismiss());
        bottomRow.addView(cancelBtn);

        // Confirm Button
        Button confirmBtn = new Button(this);
        confirmBtn.setText("✅ 选择当前目录");
        confirmBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        confirmBtn.setTypeface(Typeface.DEFAULT_BOLD);
        confirmBtn.setTextColor(Color.WHITE);
        confirmBtn.setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10));
        GradientDrawable confirmBg = new GradientDrawable();
        confirmBg.setColor(Color.parseColor("#2563EB"));
        confirmBg.setCornerRadius(dpToPx(8));
        confirmBtn.setBackground(confirmBg);
        LinearLayout.LayoutParams confirmParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.5f);
        confirmParams.leftMargin = dpToPx(8);
        confirmBtn.setLayoutParams(confirmParams);

        confirmBtn.setOnClickListener(v -> {
            String chosen = OfflineHelperCore.normalizeVirtualPath(currentBrowsePath[0]);
            targetPathEditText.setText(chosen);
            if (config.presetPaths == null) {
                config.presetPaths = new ArrayList<>();
            }
            if (!config.presetPaths.contains(chosen)) {
                config.presetPaths.add(0, chosen);
            }
            config.path = chosen;
            saveUserConfig(config);
            if (presetContainer != null) {
                renderPresetChips(presetContainer, config, targetPathEditText);
            }
            pickerDialog.dismiss();
        });
        bottomRow.addView(confirmBtn);

        rootLayout.addView(bottomRow);

        pickerDialog.setContentView(rootLayout);
        pickerDialog.show();

        // Initial load
        loadDirectoryIntoPicker(currentBrowsePath[0], config, currentBrowsePath, currentPathView, upBtn, folderListLayout, false);
    }

    private void loadDirectoryIntoPicker(
            String targetPath,
            OfflineHelperCore.OfflineConfig config,
            String[] currentBrowsePath,
            TextView currentPathView,
            Button upBtn,
            LinearLayout folderListLayout,
            boolean forceRefresh
    ) {
        String normalized = OfflineHelperCore.normalizeVirtualPath(targetPath);
        currentBrowsePath[0] = normalized;
        currentPathView.setText("当前路径: " + normalized);

        boolean isRoot = "/".equals(normalized);
        upBtn.setEnabled(!isRoot);
        upBtn.setAlpha(isRoot ? 0.4f : 1.0f);

        folderListLayout.removeAllViews();

        TextView loadingView = new TextView(this);
        loadingView.setText("⏳ 正在读取目录...");
        loadingView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        loadingView.setTextColor(Color.parseColor("#6B7280"));
        loadingView.setPadding(dpToPx(16), dpToPx(32), dpToPx(16), dpToPx(32));
        loadingView.setGravity(Gravity.CENTER);
        folderListLayout.addView(loadingView);

        new Thread(() -> {
            OfflineHelperCore.DirListResult res = OfflineHelperCore.listDirectories(normalized, config, forceRefresh, 10000);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || pickerDialog == null || !pickerDialog.isShowing()) {
                    return;
                }
                if (!normalized.equals(currentBrowsePath[0])) {
                    return;
                }

                folderListLayout.removeAllViews();

                if (!res.success) {
                    TextView errorView = new TextView(ProcessTextActivity.this);
                    String err = (res.message != null && !res.message.isEmpty()) ? res.message : ("HTTP " + res.code);
                    errorView.setText("❌ 读取失败: " + err);
                    errorView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
                    errorView.setTextColor(Color.parseColor("#DC2626"));
                    errorView.setPadding(dpToPx(12), dpToPx(12), dpToPx(12), dpToPx(8));
                    folderListLayout.addView(errorView);

                    LinearLayout actionRow = new LinearLayout(ProcessTextActivity.this);
                    actionRow.setOrientation(LinearLayout.HORIZONTAL);
                    actionRow.setGravity(Gravity.CENTER_HORIZONTAL);
                    actionRow.setPadding(0, dpToPx(4), 0, dpToPx(12));

                    Button retryBtn = new Button(ProcessTextActivity.this);
                    retryBtn.setText("🔄 重试");
                    retryBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
                    retryBtn.setTextColor(Color.parseColor("#2563EB"));
                    retryBtn.setPadding(dpToPx(12), dpToPx(6), dpToPx(12), dpToPx(6));
                    GradientDrawable retryBg = new GradientDrawable();
                    retryBg.setColor(Color.parseColor("#EFF6FF"));
                    retryBg.setStroke(dpToPx(1), Color.parseColor("#BFDBFE"));
                    retryBg.setCornerRadius(dpToPx(6));
                    retryBtn.setBackground(retryBg);
                    retryBtn.setOnClickListener(v -> loadDirectoryIntoPicker(normalized, config, currentBrowsePath, currentPathView, upBtn, folderListLayout, true));
                    actionRow.addView(retryBtn);

                    if (!"/".equals(normalized)) {
                        Button fallbackRootBtn = new Button(ProcessTextActivity.this);
                        fallbackRootBtn.setText("📂 退回根目录 (/)");
                        fallbackRootBtn.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
                        fallbackRootBtn.setTextColor(Color.parseColor("#4B5563"));
                        fallbackRootBtn.setPadding(dpToPx(12), dpToPx(6), dpToPx(12), dpToPx(6));
                        GradientDrawable fbBg = new GradientDrawable();
                        fbBg.setColor(Color.parseColor("#F3F4F6"));
                        fbBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
                        fbBg.setCornerRadius(dpToPx(6));
                        fallbackRootBtn.setBackground(fbBg);
                        LinearLayout.LayoutParams fbParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                        fbParams.leftMargin = dpToPx(8);
                        fallbackRootBtn.setLayoutParams(fbParams);
                        fallbackRootBtn.setOnClickListener(v -> loadDirectoryIntoPicker("/", config, currentBrowsePath, currentPathView, upBtn, folderListLayout, false));
                        actionRow.addView(fallbackRootBtn);
                    }

                    folderListLayout.addView(actionRow);
                    return;
                }

                if (res.directories == null || res.directories.isEmpty()) {
                    TextView emptyView = new TextView(ProcessTextActivity.this);
                    emptyView.setText("（当前目录下无子文件夹，可直接点击下方按钮选择此目录）");
                    emptyView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
                    emptyView.setTextColor(Color.parseColor("#6B7280"));
                    emptyView.setPadding(dpToPx(16), dpToPx(24), dpToPx(16), dpToPx(24));
                    emptyView.setGravity(Gravity.CENTER);
                    folderListLayout.addView(emptyView);
                    return;
                }

                for (String dirName : res.directories) {
                    LinearLayout itemRow = new LinearLayout(ProcessTextActivity.this);
                    itemRow.setOrientation(LinearLayout.HORIZONTAL);
                    itemRow.setGravity(Gravity.CENTER_VERTICAL);
                    itemRow.setPadding(dpToPx(12), dpToPx(10), dpToPx(12), dpToPx(10));
                    itemRow.setClickable(true);
                    itemRow.setFocusable(true);

                    GradientDrawable itemBg = new GradientDrawable();
                    itemBg.setColor(Color.WHITE);
                    itemBg.setStroke(dpToPx(1), Color.parseColor("#E5E7EB"));
                    itemBg.setCornerRadius(dpToPx(6));
                    itemRow.setBackground(itemBg);

                    LinearLayout.LayoutParams itemParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                    itemParams.bottomMargin = dpToPx(6);
                    itemRow.setLayoutParams(itemParams);

                    TextView nameView = new TextView(ProcessTextActivity.this);
                    nameView.setText("📁  " + dirName);
                    nameView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
                    nameView.setTextColor(Color.parseColor("#1F2937"));
                    nameView.setSingleLine(true);
                    nameView.setEllipsize(TextUtils.TruncateAt.END);
                    LinearLayout.LayoutParams nameParams = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
                    nameView.setLayoutParams(nameParams);
                    itemRow.addView(nameView);

                    TextView arrowView = new TextView(ProcessTextActivity.this);
                    arrowView.setText("›");
                    arrowView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
                    arrowView.setTextColor(Color.parseColor("#9CA3AF"));
                    arrowView.setPadding(dpToPx(4), 0, dpToPx(4), 0);
                    itemRow.addView(arrowView);

                    final String subPath = OfflineHelperCore.joinVirtualPath(normalized, dirName);
                    itemRow.setOnClickListener(v -> {
                        loadDirectoryIntoPicker(subPath, config, currentBrowsePath, currentPathView, upBtn, folderListLayout, false);
                    });

                    folderListLayout.addView(itemRow);
                }
            });
        }).start();
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
        if (pickerDialog != null && pickerDialog.isShowing()) {
            pickerDialog.dismiss();
        }
        if (currentDialog != null && currentDialog.isShowing()) {
            currentDialog.dismiss();
        }
        super.onDestroy();
    }
}
