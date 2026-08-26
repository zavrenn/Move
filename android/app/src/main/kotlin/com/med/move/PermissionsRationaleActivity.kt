package com.med.move

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.rgb(8, 11, 10)
        window.navigationBarColor = Color.rgb(8, 11, 10)

        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(28), dp(28), dp(28), dp(28))
            setBackgroundColor(Color.rgb(8, 11, 10))
        }
        content.addView(TextView(this).apply {
            text = "Move & your steps"
            textSize = 28f
            setTextColor(Color.rgb(241, 245, 240))
        })
        content.addView(TextView(this).apply {
            text = "Move reads only your daily step totals from Health Connect. " +
                "It never writes health data or sends it off this device. " +
                "Daily totals are cached locally for your dashboard and progress views."
            textSize = 17f
            setTextColor(Color.rgb(156, 168, 159))
            setLineSpacing(0f, 1.25f)
            setPadding(0, dp(18), 0, dp(26))
        })
        content.addView(Button(this).apply {
            text = "Close"
            setOnClickListener { finish() }
        }, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(54)))
        setContentView(content)
    }
}
