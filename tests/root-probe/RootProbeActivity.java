package com.example.rootprobe;

import android.app.Activity;
import android.os.Bundle;
import android.util.TypedValue;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

public final class RootProbeActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        TextView result = new TextView(this);
        int padding = (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                24,
                getResources().getDisplayMetrics()
        );
        result.setPadding(padding, padding, padding, padding);
        result.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18);
        result.setTextIsSelectable(true);
        result.setText("Requesting Magisk root...");
        setContentView(result);

        new Thread(() -> runRootProbe(result), "root-probe").start();
    }

    private void runRootProbe(TextView result) {
        StringBuilder output = new StringBuilder();
        int exitCode = -1;
        try {
            Process process = new ProcessBuilder("su", "-c", "id")
                    .redirectErrorStream(true)
                    .start();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (output.length() > 0) {
                        output.append('\n');
                    }
                    output.append(line);
                }
            }
            exitCode = process.waitFor();
        } catch (Exception exception) {
            output.append(exception.getClass().getSimpleName())
                    .append(": ")
                    .append(exception.getMessage());
        }

        String message = "exit=" + exitCode + "\n" + output;
        runOnUiThread(() -> result.setText(message));
    }
}
