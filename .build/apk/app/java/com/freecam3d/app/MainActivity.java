package com.freecam3d.app;

import android.Manifest;
import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.Toast;
import androidx.webkit.WebViewAssetLoader;
import androidx.webkit.WebViewClientCompat;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

/**
 * Thin WebView shell around the untouched single-file webapp (assets/index.html).
 * - WebViewAssetLoader serves assets at https://appassets.androidplatform.net/assets/
 *   so the page gets a SECURE CONTEXT -> getUserMedia(camera) works inside the WebView.
 * - Camera permission requests from the page are mapped to the Android runtime permission.
 * - The page's global downloadBlob(blob, fn) is overridden at page-load time to route
 *   exports through FreeCamNative.saveB64 -> MediaStore Downloads. index.html itself is
 *   never modified.
 */
public class MainActivity extends Activity {
    private static final int REQ_CAM = 42;
    private static final String HOST = "appassets.androidplatform.net";

    private WebView web;
    private WebViewAssetLoader assetLoader;
    private PermissionRequest pendingCam;

    private class NativeSaver {
        @JavascriptInterface
        public void saveB64(String b64, String name) {
            final byte[] data = Base64.decode(b64, Base64.DEFAULT);
            final String where = saveFile(name, data);
            runOnUiThread(new Runnable() {
                public void run() {
                    Toast.makeText(MainActivity.this, "Gespeichert: " + where, Toast.LENGTH_LONG).show();
                }
            });
        }
    }

    private static String mimeFor(String name) {
        String n = (name == null ? "" : name.toLowerCase());
        if (n.endsWith(".zip")) return "application/zip";
        if (n.endsWith(".json")) return "application/json";
        if (n.endsWith(".obj")) return "text/plain";
        if (n.endsWith(".png")) return "image/png";
        if (n.endsWith(".jpg") || n.endsWith(".jpeg")) return "image/jpeg";
        if (n.endsWith(".webm")) return "video/webm";
        return "application/octet-stream";
    }

    private String saveFile(String name, byte[] data) {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                ContentValues cv = new ContentValues();
                cv.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
                cv.put(MediaStore.MediaColumns.MIME_TYPE, mimeFor(name));
                cv.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
                OutputStream os = getContentResolver().openOutputStream(uri);
                try { os.write(data); } finally { os.close(); }
                return "Download/" + name;
            } else {
                File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                File f = new File(dir, name);
                FileOutputStream os = new FileOutputStream(f);
                try { os.write(data); } finally { os.close(); }
                return f.getAbsolutePath();
            }
        } catch (Exception e) {
            return "FEHLER: " + e.getMessage();
        }
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] granted) {
        if (code == REQ_CAM && pendingCam != null) {
            if (granted.length > 0 && granted[0] == PackageManager.PERMISSION_GRANTED) {
                pendingCam.grant(pendingCam.getResources());
            } else {
                pendingCam.deny();
            }
            pendingCam = null;
        }
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        assetLoader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();
        web = new WebView(this);
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        web.addJavascriptInterface(new NativeSaver(), "FreeCamNative");
        web.setWebViewClient(new WebViewClientCompat() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest req) {
                return assetLoader.shouldInterceptRequest(req.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest req) {
                Uri u = req.getUrl();
                if (HOST.equals(u.getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception ignored) { }
                return true;
            }

            @Override
            public void onPageFinished(WebView v, String url) {
                // Route downloadBlob(blob, fn) into the native saver; falls back to the
                // original <a download> path if the bridge or read fails. Idempotent.
                v.evaluateJavascript(
                    "(function(){if(window.__fcPatched)return;window.__fcPatched=1;" +
                    "if(typeof window.downloadBlob==='function'){var orig=window.downloadBlob;" +
                    "window.downloadBlob=function(blob,fn){try{" +
                    "var r=new FileReader();r.onerror=function(){orig(blob,fn);};" +
                    "r.onload=function(){try{var s=String(r.result);" +
                    "FreeCamNative.saveB64(s.substring(s.indexOf(',')+1),fn||'download');}catch(e){orig(blob,fn);}};" +
                    "r.readAsDataURL(blob);}catch(e){orig(blob,fn);}};}})();", null);
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest req) {
                runOnUiThread(new Runnable() {
                    public void run() {
                        for (String r : req.getResources()) {
                            if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) {
                                if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                                    req.grant(req.getResources());
                                } else {
                                    pendingCam = req;
                                    requestPermissions(new String[]{Manifest.permission.CAMERA}, REQ_CAM);
                                }
                                return;
                            }
                        }
                        req.deny();
                    }
                });
            }
        });
        web.loadUrl("https://" + HOST + "/assets/index.html");
    }
}
