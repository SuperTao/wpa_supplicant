
打印函数
enum {
	MSG_EXCESSIVE, MSG_MSGDUMP, MSG_DEBUG, MSG_INFO, MSG_WARNING, MSG_ERROR
};

src/utils/wpa_debug.c
void wpa_printf(int level, const char *fmt, ...)
{
	va_list ap;     //可变参

	if (level >= wpa_debug_level) {           // 日志等级判断
#ifdef CONFIG_ANDROID_LOG
		va_start(ap, fmt);
		__android_log_vprint(wpa_to_android_level(level),
				     ANDROID_LOG_NAME, fmt, ap);
		va_end(ap);
#else /* CONFIG_ANDROID_LOG */
#ifdef CONFIG_DEBUG_SYSLOG
		if (wpa_debug_syslog) {
			va_start(ap, fmt);
			vsyslog(syslog_priority(level), fmt, ap);
			va_end(ap);
		}
#endif /* CONFIG_DEBUG_SYSLOG */
		wpa_debug_print_timestamp();    // 打印时间戳
#ifdef CONFIG_DEBUG_FILE
		if (out_file) {                 // 写文件
			va_start(ap, fmt);
			vfprintf(out_file, fmt, ap);
			fprintf(out_file, "\n");
			va_end(ap);
		}
#endif /* CONFIG_DEBUG_FILE */
		if (!wpa_debug_syslog && !out_file) {      // 直接打印终端
			va_start(ap, fmt);
			vprintf(fmt, ap);
			printf("\n");                         // 打印\n
			va_end(ap);
		}
#endif /* CONFIG_ANDROID_LOG */
	}

#ifdef CONFIG_DEBUG_LINUX_TRACING
	if (wpa_debug_tracing_file != NULL) {
		va_start(ap, fmt);
		fprintf(wpa_debug_tracing_file, WPAS_TRACE_PFX, level);
		vfprintf(wpa_debug_tracing_file, fmt, ap);
		fprintf(wpa_debug_tracing_file, "\n");
		fflush(wpa_debug_tracing_file);      // 刷新文件，写flash的时候需要
		va_end(ap);
	}
#endif /* CONFIG_DEBUG_LINUX_TRACING */
}

16进制打印
// 以16进制打印数据
static void _wpa_hexdump(int level, const char *title, const u8 *buf,
			 size_t len, int show, int only_syslog)
		if (!wpa_debug_syslog && !out_file) {
		printf("%s - hexdump(len=%lu):", title, (unsigned long) len);
		if (buf == NULL) {
			printf(" [NULL]");
		} else if (show) {
			for (i = 0; i < len; i++)
				printf(" %02x", buf[i]);
		} else {
			printf(" [REMOVED]");
		}
		printf("\n");


assic码打印

// assic码打印
static void _wpa_hexdump_ascii(int level, const char *title, const void *buf,
			       size_t len, int show)
{
	size_t i, llen;
	const u8 *pos = buf;
	// 一行只打印16个数据
	const size_t line_len = 16;


	if (level < wpa_debug_level)
		return;
	...
	...

	wpa_debug_print_timestamp();
   ...
   ...
// 打印title和数据长度
		fprintf(out_file, "%s - hexdump_ascii(len=%lu):\n",
			title, (unsigned long) len);
		while (len) {
			// 判断一行要打印的数据长度，最大16个数据
			llen = len > line_len ? line_len : len;
			fprintf(out_file, "    ");
			// 打印一行的16进制
			for (i = 0; i < llen; i++)
				fprintf(out_file, " %02x", pos[i]);
			// 剩余的数据不满16个，就打印空格
			for (i = llen; i < line_len; i++)
				fprintf(out_file, "   ");
			fprintf(out_file, "   ");
			// 同一行，打印assic码
			for (i = 0; i < llen; i++) {
				// 判断字符是否可打印
				if (isprint(pos[i]))
					fprintf(out_file, "%c", pos[i]);
				else
					fprintf(out_file, "_");
			}
			// 为了对齐，少于16个数据，打印空行
			for (i = llen; i < line_len; i++)
				fprintf(out_file, " ");
			fprintf(out_file, "\n");
			pos += llen;
			len -= llen;
		
}


void wpa_hexdump_ascii(int level, const char *title, const void *buf,
		       size_t len)
{
	_wpa_hexdump_ascii(level, title, buf, len, 1);
}
