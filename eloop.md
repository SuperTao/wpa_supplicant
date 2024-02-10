### eloop

* 使用epoll/kqueue/select循环检查timeout, read, write, exception表中的异常

* 获取timeout链表中的超时事件,提取最近的超时事件，判断是否有事件超时。超时就运行超时函数，并将事件移除，等待select下一次超时。

* 监听readers, writers，exception table中的变化, 执行对应的函数

src/utils/eloop.c
```
void eloop_run(void)
{
#ifdef CONFIG_ELOOP_SELECT
	fd_set *rfds, *wfds, *efds;
	struct timeval _tv;
#endif /* CONFIG_ELOOP_SELECT */
	int res;
	struct os_reltime tv, now;

#ifdef CONFIG_ELOOP_SELECT
	rfds = os_malloc(sizeof(*rfds));
	wfds = os_malloc(sizeof(*wfds));
	efds = os_malloc(sizeof(*efds));
	if (rfds == NULL || wfds == NULL || efds == NULL)
		goto out;
#endif /* CONFIG_ELOOP_SELECT */
// eloop循环
	while (!eloop.terminate &&
	       (!dl_list_empty(&eloop.timeout) || eloop.readers.count > 0 ||
		eloop.writers.count > 0 || eloop.exceptions.count > 0)) {
		struct eloop_timeout *timeout;

		if (eloop.pending_terminate) {
			/*
			 * This may happen in some corner cases where a signal
			 * is received during a blocking operation. We need to
			 * process the pending signals and exit if requested to
			 * avoid hitting the SIGALRM limit if the blocking
			 * operation took more than two seconds.
			 */
			eloop_process_pending_signals();
			if (eloop.terminate)
				break;
		}
// 更新监听的   socket的最近一次的超时事件，从链表中获取
		timeout = dl_list_first(&eloop.timeout, struct eloop_timeout,
					list);
		if (timeout) {
// 获取现在的时间
			os_get_reltime(&now);
// 现在的时间比timeout里面的时间早
			if (os_reltime_before(&now, &timeout->time))
// 计算到下一次超时时间要多久
				os_reltime_sub(&timeout->time, &now, &tv);
			else
				tv.sec = tv.usec = 0;
#if defined(CONFIG_ELOOP_POLL) || defined(CONFIG_ELOOP_EPOLL)
			timeout_ms = tv.sec * 1000 + tv.usec / 1000;
#endif /* defined(CONFIG_ELOOP_POLL) || defined(CONFIG_ELOOP_EPOLL) */
#ifdef CONFIG_ELOOP_SELECT
// 更新超时时间
			_tv.tv_sec = tv.sec;
			_tv.tv_usec = tv.usec;
#endif /* CONFIG_ELOOP_SELECT */
		}

#ifdef CONFIG_ELOOP_SELECT
// 监听readers, writers, exceptions中的fd,以及timeout事件
		eloop_sock_table_set_fds(&eloop.readers, rfds);
		eloop_sock_table_set_fds(&eloop.writers, wfds);
		eloop_sock_table_set_fds(&eloop.exceptions, efds);
		res = select(eloop.max_sock + 1, rfds, wfds, efds,
			     timeout ? &_tv : NULL);
#endif /* CONFIG_ELOOP_SELECT */

		if (res < 0 && errno != EINTR && errno != 0) {
			wpa_printf(MSG_ERROR, "eloop: %s: %s",
#ifdef CONFIG_ELOOP_SELECT
				   "select"
#endif /* CONFIG_ELOOP_SELECT */

				   , strerror(errno));
			goto out;
		}

		eloop.readers.changed = 0;
		eloop.writers.changed = 0;
		eloop.exceptions.changed = 0;
// 处理等待的信号，系统发送的一些信号
		eloop_process_pending_signals();

// 判断是否有超时事件到来
		/* check if some registered timeouts have occurred */
		timeout = dl_list_first(&eloop.timeout, struct eloop_timeout,
					list);
		if (timeout) {
			os_get_reltime(&now);
// 链表中的事件比现在的事件早，说明已经超时
			if (!os_reltime_before(&now, &timeout->time)) {
// 执行超时事件
				void *eloop_data = timeout->eloop_data;
				void *user_data = timeout->user_data;
				eloop_timeout_handler handler =
					timeout->handler;
// 从链表中移除
				eloop_remove_timeout(timeout);
// 调用回调函数
				handler(eloop_data, user_data);
			}

		}

		if (res <= 0)
			continue;
// 检查socket是由已经关闭或者处理了，就需要忽略这一次的事件
		if (eloop.readers.changed ||
		    eloop.writers.changed ||
		    eloop.exceptions.changed) {
			 /*
			  * Sockets may have been closed and reopened with the
			  * same FD in the signal or timeout handlers, so we
			  * must skip the previous results and check again
			  * whether any of the currently registered sockets have
			  * events.
			  */
			continue;
		}

#ifdef CONFIG_ELOOP_SELECT
// for循环，查找哪个fd有数据变化，调用回调函数
		eloop_sock_table_dispatch(&eloop.readers, rfds);
		eloop_sock_table_dispatch(&eloop.writers, wfds);
		eloop_sock_table_dispatch(&eloop.exceptions, efds);
#endif /* CONFIG_ELOOP_SELECT */
#ifdef CONFIG_ELOOP_EPOLL
		eloop_sock_table_dispatch(eloop.epoll_events, res);
#endif /* CONFIG_ELOOP_EPOLL */
#ifdef CONFIG_ELOOP_KQUEUE
		eloop_sock_table_dispatch(eloop.kqueue_events, res);
#endif /* CONFIG_ELOOP_KQUEUE */
	}

	eloop.terminate = 0;
out:
#ifdef CONFIG_ELOOP_SELECT
	os_free(rfds);
	os_free(wfds);
	os_free(efds);
#endif /* CONFIG_ELOOP_SELECT */
	return;
}
```

```
#ifdef CONFIG_ELOOP_SELECT
// 设置监听的fd
static void eloop_sock_table_set_fds(struct eloop_sock_table *table,
				     fd_set *fds)
{
	size_t i;

	FD_ZERO(fds);

	if (table->table == NULL)
		return;

	for (i = 0; i < table->count; i++) {
		assert(table->table[i].sock >= 0);
		FD_SET(table->table[i].sock, fds);
	}
}

// 判断是否有事件发生，进行设置
static void eloop_sock_table_dispatch(struct eloop_sock_table *table,
				      fd_set *fds)
{
	size_t i;

	if (table == NULL || table->table == NULL)
		return;

	table->changed = 0;
	for (i = 0; i < table->count; i++) {
		if (FD_ISSET(table->table[i].sock, fds)) {
			table->table[i].handler(table->table[i].sock,
						table->table[i].eloop_data,
						table->table[i].user_data);
			if (table->changed)
				break;
		}
	}
}

#endif /* CONFIG_ELOOP_SELECT */
```
