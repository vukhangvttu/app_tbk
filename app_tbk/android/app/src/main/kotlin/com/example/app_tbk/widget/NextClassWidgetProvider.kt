package com.example.app_tbk.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import com.example.app_tbk.R
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * Widget màn hình chính: buổi học hiện tại / tiếp theo.
 *
 * Dữ liệu do phía Dart (NextClassWidgetService) ghi vào HomeWidgetPreferences.
 * Provider này chỉ đọc dữ liệu + tự tính lại nhãn thời gian mỗi lần Android
 * gọi onUpdate (mỗi 30 phút theo updatePeriodMillis) nên đếm ngược không bị
 * "đứng" khi app không được mở.
 */
class NextClassWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.next_class_widget)

            // Chạm vào widget → mở app
            val launchIntent =
                context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pending = PendingIntent.getActivity(
                    context, 0, launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                views.setOnClickPendingIntent(R.id.widget_root, pending)
            }

            val state = widgetData.getString("nc_state", "empty") ?: "empty"
            val subject = widgetData.getString("nc_subject", null)

            if (state == "empty" || subject.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_header, "MÔN HỌC TIẾP THEO")
                views.setViewVisibility(R.id.widget_status, View.GONE)
                views.setViewVisibility(R.id.widget_subject, View.GONE)
                views.setViewVisibility(R.id.widget_time, View.GONE)
                views.setViewVisibility(R.id.widget_room, View.GONE)
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            } else {
                val kind = widgetData.getString("nc_kind", "hoc") ?: "hoc"
                val time = widgetData.getString("nc_time", "") ?: ""
                val room = widgetData.getString("nc_room", "") ?: ""
                val teacher = widgetData.getString("nc_teacher", "") ?: ""
                val startMs = widgetData.getLong("nc_start_ms", 0L)
                val endMs = widgetData.getLong("nc_end_ms", 0L)
                val now = System.currentTimeMillis()

                views.setViewVisibility(R.id.widget_empty, View.GONE)
                views.setViewVisibility(R.id.widget_subject, View.VISIBLE)
                views.setViewVisibility(R.id.widget_time, View.VISIBLE)

                views.setTextViewText(
                    R.id.widget_header,
                    if (kind == "thi") "LỊCH THI SẮP TỚI" else "MÔN HỌC TIẾP THEO"
                )
                views.setTextViewText(R.id.widget_subject, subject)

                // Nhãn trạng thái tự tính lại theo giờ hiện tại
                val dangHoc = state == "current" || (startMs > 0 && now >= startMs && now < endMs)
                val status = when {
                    dangHoc && endMs > now ->
                        "Đang học • còn ${dinhDangKhoang(endMs - now)} nữa tan"
                    startMs > now && startMs - now < 24 * 60 * 60 * 1000L ->
                        "Bắt đầu sau ${dinhDangKhoang(startMs - now)}"
                    else -> ""
                }
                if (status.isEmpty()) {
                    views.setViewVisibility(R.id.widget_status, View.GONE)
                } else {
                    views.setViewVisibility(R.id.widget_status, View.VISIBLE)
                    views.setTextViewText(R.id.widget_status, status)
                }

                views.setTextViewText(R.id.widget_time, "🕐 $time • ${nhanNgay(startMs)}")

                val roomLine = buildString {
                    if (room.isNotEmpty()) append("📍 $room")
                    if (teacher.isNotEmpty()) {
                        if (isNotEmpty()) append("  •  ")
                        append("GV: $teacher")
                    }
                }
                if (roomLine.isEmpty()) {
                    views.setViewVisibility(R.id.widget_room, View.GONE)
                } else {
                    views.setViewVisibility(R.id.widget_room, View.VISIBLE)
                    views.setTextViewText(R.id.widget_room, roomLine)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun dinhDangKhoang(ms: Long): String {
        if (ms <= 0) return "ít phút"
        val tongPhut = ms / 60000
        val gio = tongPhut / 60
        val phut = tongPhut % 60
        return when {
            gio > 0 && phut > 0 -> "$gio giờ $phut phút"
            gio > 0 -> "$gio giờ"
            else -> "$phut phút"
        }
    }

    private fun nhanNgay(ms: Long): String {
        if (ms <= 0) return ""
        val cal = Calendar.getInstance().apply { timeInMillis = ms }
        val homNay = Calendar.getInstance()
        val ngayMai = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }

        fun cungNgay(a: Calendar, b: Calendar): Boolean =
            a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
                a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

        return when {
            cungNgay(cal, homNay) -> "Hôm nay"
            cungNgay(cal, ngayMai) -> "Ngày mai"
            else -> {
                val thu = when (cal.get(Calendar.DAY_OF_WEEK)) {
                    Calendar.MONDAY -> "Thứ 2"
                    Calendar.TUESDAY -> "Thứ 3"
                    Calendar.WEDNESDAY -> "Thứ 4"
                    Calendar.THURSDAY -> "Thứ 5"
                    Calendar.FRIDAY -> "Thứ 6"
                    Calendar.SATURDAY -> "Thứ 7"
                    else -> "Chủ nhật"
                }
                val d = cal.get(Calendar.DAY_OF_MONTH)
                val m = cal.get(Calendar.MONTH) + 1
                "$thu • ${"%02d/%02d".format(d, m)}"
            }
        }
    }
}
