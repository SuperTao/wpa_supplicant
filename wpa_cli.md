### wpa_cli

两种运行模式

* 交互模式

* 后台运行

### 代码分析

wpa_supplicant/wpa_cli.c

```
int main(int argc, char *argv[])

	if (interactive)
		printf("%s\n\n%s\n\n", wpa_cli_version, cli_license);
// 初始化eloop循环
	if (eloop_init())
		return -1;
// 创建socket，注册回调函数
	if (global && wpa_cli_open_global_ctrl() < 0)
		return -1;
// 注册系统的信号SIGINT, SIGTERM处理函数
	eloop_register_signal_terminate(wpa_cli_terminate, NULL);
// 获取接口名称
	if (ctrl_ifname == NULL)
		ctrl_ifname = wpa_cli_get_default_ifname();
// 重连?
	if (reconnect && action_file && ctrl_ifname) {
		while (!wpa_cli_quit) {
			if (ctrl_conn)
				wpa_cli_action(ctrl_conn);
			else
				os_sleep(1, 0);
			wpa_cli_close_connection();
			wpa_cli_open_connection(ctrl_ifname, 0);
			if (ctrl_conn) {
				if (wpa_ctrl_attach(ctrl_conn) != 0)
					wpa_cli_close_connection();
				else
					wpa_cli_attached = 1;
			}
		}
	} else if (interactive) {
// 交互模式
		wpa_cli_interactive();
	} else {
		if (!global &&
		    wpa_cli_open_connection(ctrl_ifname, 0) < 0) {
			fprintf(stderr, "Failed to connect to non-global "
				"ctrl_ifname: %s  error: %s\n",
				ctrl_ifname ? ctrl_ifname : "(nil)",
				strerror(errno));
			return -1;
		}

		if (action_file) {
			if (wpa_ctrl_attach(ctrl_conn) == 0) {
				wpa_cli_attached = 1;
			} else {
				printf("Warning: Failed to attach to "
				       "wpa_supplicant.\n");
				return -1;
			}
		}
// 以进程方式运行
		if (daemonize && os_daemonize(pid_file) && eloop_sock_requeue())
			return -1;

		if (action_file)
			wpa_cli_action(ctrl_conn);
		else
			ret = wpa_request(ctrl_conn, argc - optind,
					  &argv[optind]);
	}

	os_free(ctrl_ifname);
	eloop_destroy();
	wpa_cli_cleanup();

	return ret;
}
```

```
int eloop_init(void)
{
	os_memset(&eloop, 0, sizeof(eloop));
// 超时链表初始化
	dl_list_init(&eloop.timeout);
#ifdef CONFIG_ELOOP_EPOLL
	eloop.epollfd = epoll_create1(0);
	if (eloop.epollfd < 0) {
		wpa_printf(MSG_ERROR, "%s: epoll_create1 failed. %s",
			   __func__, strerror(errno));
		return -1;
	}
#endif /* CONFIG_ELOOP_EPOLL */
#ifdef CONFIG_ELOOP_KQUEUE
	eloop.kqueuefd = kqueue();
	if (eloop.kqueuefd < 0) {
		wpa_printf(MSG_ERROR, "%s: kqueue failed: %s",
			   __func__, strerror(errno));
		return -1;
	}
#endif /* CONFIG_ELOOP_KQUEUE */
#if defined(CONFIG_ELOOP_EPOLL) || defined(CONFIG_ELOOP_KQUEUE)
// eloop类型初始化
	eloop.readers.type = EVENT_TYPE_READ;
	eloop.writers.type = EVENT_TYPE_WRITE;
	eloop.exceptions.type = EVENT_TYPE_EXCEPTION;
#endif /* CONFIG_ELOOP_EPOLL || CONFIG_ELOOP_KQUEUE */
#ifdef WPA_TRACE
	signal(SIGSEGV, eloop_sigsegv_handler);
#endif /* WPA_TRACE */
	return 0;
}
```

```
static int wpa_cli_open_global_ctrl(void)
{
#ifdef CONFIG_CTRL_IFACE_NAMED_PIPE
	ctrl_conn = wpa_ctrl_open(NULL);	// 有名管道
#else /* CONFIG_CTRL_IFACE_NAMED_PIPE */
	ctrl_conn = wpa_ctrl_open(global);
#endif /* CONFIG_CTRL_IFACE_NAMED_PIPE */
	if (!ctrl_conn) {
		fprintf(stderr,
			"Failed to connect to wpa_supplicant global interface: %s  error: %s\n",
			global, strerror(errno));
		return -1;
	}
// 交互模式
	if (interactive) {
		update_ifnames(ctrl_conn);
// 创建socket
		mon_conn = wpa_ctrl_open(global);
		if (mon_conn) {
			if (wpa_ctrl_attach(mon_conn) == 0) {
				wpa_cli_attached = 1;
// 注册eloop监听读数据。回调函数wpa_cli_mon_receive
				eloop_register_read_sock(
					wpa_ctrl_get_fd(mon_conn),
// 事件回调函数
					wpa_cli_mon_receive,
					NULL, NULL);
			} else {
				printf("Failed to open monitor connection through global control interface\n");
			}
		}
		update_stations(ctrl_conn);
	}

	return 0;
}
```


```
static void wpa_cli_interactive(void)
{
	printf("\nInteractive mode\n\n");

	eloop_register_timeout(0, 0, try_connection, NULL, NULL);
// 事件循环
	eloop_run();
// 删除重连事件
	eloop_cancel_timeout(try_connection, NULL, NULL);

	cli_txt_list_flush(&p2p_peers);
	cli_txt_list_flush(&p2p_groups);
	cli_txt_list_flush(&bsses);
	cli_txt_list_flush(&ifnames);
	cli_txt_list_flush(&creds);
	cli_txt_list_flush(&networks);
	if (edit_started)
		edit_deinit(hfile, wpa_cli_edit_filter_history_cb);
	os_free(hfile);
	eloop_cancel_timeout(wpa_cli_ping, NULL, NULL);
	wpa_cli_close_connection();
}
```


```
void eloop_run(void)
{
#ifdef CONFIG_ELOOP_POLL
	int num_poll_fds;
	int timeout_ms = 0;
#endif /* CONFIG_ELOOP_POLL */
#ifdef CONFIG_ELOOP_SELECT
	fd_set *rfds, *wfds, *efds;
	struct timeval _tv;
#endif /* CONFIG_ELOOP_SELECT */
#ifdef CONFIG_ELOOP_EPOLL
	int timeout_ms = -1;
#endif /* CONFIG_ELOOP_EPOLL */
#ifdef CONFIG_ELOOP_KQUEUE
	struct timespec ts;
#endif /* CONFIG_ELOOP_KQUEUE */
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
#ifdef CONFIG_ELOOP_KQUEUE
			ts.tv_sec = tv.sec;
			ts.tv_nsec = tv.usec * 1000L;
#endif /* CONFIG_ELOOP_KQUEUE */
		}

#ifdef CONFIG_ELOOP_POLL
		num_poll_fds = eloop_sock_table_set_fds(
			&eloop.readers, &eloop.writers, &eloop.exceptions,
			eloop.pollfds, eloop.pollfds_map,
			eloop.max_pollfd_map);
		res = poll(eloop.pollfds, num_poll_fds,
			   timeout ? timeout_ms : -1);
#endif /* CONFIG_ELOOP_POLL */
#ifdef CONFIG_ELOOP_SELECT
// 监听readers, writers, exceptions中的fd,以及timeout事件
		eloop_sock_table_set_fds(&eloop.readers, rfds);
		eloop_sock_table_set_fds(&eloop.writers, wfds);
		eloop_sock_table_set_fds(&eloop.exceptions, efds);
		res = select(eloop.max_sock + 1, rfds, wfds, efds,
			     timeout ? &_tv : NULL);
#endif /* CONFIG_ELOOP_SELECT */
#ifdef CONFIG_ELOOP_EPOLL
		if (eloop.count == 0) {
			res = 0;
		} else {
			res = epoll_wait(eloop.epollfd, eloop.epoll_events,
					 eloop.count, timeout_ms);
		}
#endif /* CONFIG_ELOOP_EPOLL */
#ifdef CONFIG_ELOOP_KQUEUE
		if (eloop.count == 0) {
			res = 0;
		} else {
			res = kevent(eloop.kqueuefd, NULL, 0,
				     eloop.kqueue_events, eloop.kqueue_nevents,
				     timeout ? &ts : NULL);
		}
#endif /* CONFIG_ELOOP_KQUEUE */
		if (res < 0 && errno != EINTR && errno != 0) {
			wpa_printf(MSG_ERROR, "eloop: %s: %s",
#ifdef CONFIG_ELOOP_POLL
				   "poll"
#endif /* CONFIG_ELOOP_POLL */
#ifdef CONFIG_ELOOP_SELECT
				   "select"
#endif /* CONFIG_ELOOP_SELECT */
#ifdef CONFIG_ELOOP_EPOLL
				   "epoll"
#endif /* CONFIG_ELOOP_EPOLL */
#ifdef CONFIG_ELOOP_KQUEUE
				   "kqueue"
#endif /* CONFIG_ELOOP_EKQUEUE */

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

#ifdef CONFIG_ELOOP_POLL
		eloop_sock_table_dispatch(&eloop.readers, &eloop.writers,
					  &eloop.exceptions, eloop.pollfds_map,
					  eloop.max_pollfd_map);
#endif /* CONFIG_ELOOP_POLL */
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

### 命令发送

src/common/wpa_ctrl.c

#### 同步接口wpa_ctrl_request

* 被系统命令中断，进行重发

* 读取的时候，select超时时间10秒

```
#ifdef CTRL_IFACE_SOCKET
int wpa_ctrl_request(struct wpa_ctrl *ctrl, const char *cmd, size_t cmd_len,
		     char *reply, size_t *reply_len,
		     void (*msg_cb)(char *msg, size_t len))
{
	struct timeval tv;
	struct os_reltime started_at;
	int res;
	fd_set rfds;
	const char *_cmd;
	char *cmd_buf = NULL;
	size_t _cmd_len;

#ifdef CONFIG_CTRL_IFACE_UDP
// 有缓存
	if (ctrl->cookie) {
		char *pos;
// 把cookie的内容也一起发送
		_cmd_len = os_strlen(ctrl->cookie) + 1 + cmd_len;
		cmd_buf = os_malloc(_cmd_len);
		if (cmd_buf == NULL)
			return -1;
		_cmd = cmd_buf;
		pos = cmd_buf;
// 先复制cookie内容
		os_strlcpy(pos, ctrl->cookie, _cmd_len);
// 更新长度
		pos += os_strlen(ctrl->cookie);
// 添加' '
		*pos++ = ' ';
// 复制要发送的内容
		os_memcpy(pos, cmd, cmd_len);
	} else
#endif /* CONFIG_CTRL_IFACE_UDP */
	{
		_cmd = cmd;
		_cmd_len = cmd_len;
	}

	errno = 0;
	started_at.sec = 0;
	started_at.usec = 0;
retry_send:
	if (send(ctrl->s, _cmd, _cmd_len, 0) < 0) {
		if (errno == EAGAIN || errno == EBUSY || errno == EWOULDBLOCK)
		{
			/*
			 * Must be a non-blocking socket... Try for a bit
			 * longer before giving up.
			 */
// 获取发送的时间
			if (started_at.sec == 0)
				os_get_reltime(&started_at);
			else {
				struct os_reltime n;
// 获取现在的时间
				os_get_reltime(&n);
				/* Try for a few seconds. */
// 重试5秒钟
				if (os_reltime_expired(&n, &started_at, 5))
					goto send_err;
			}
			os_sleep(1, 0);
			goto retry_send;
		}
	send_err:
		os_free(cmd_buf);
		return -1;
	}
	os_free(cmd_buf);

	for (;;) {
// 超时时间10秒
		tv.tv_sec = 10;
		tv.tv_usec = 0;
		FD_ZERO(&rfds);
		FD_SET(ctrl->s, &rfds);
		res = select(ctrl->s + 1, &rfds, NULL, NULL, &tv);
// 被中断时，就继续阻塞，等待读事件
		if (res < 0 && errno == EINTR)
			continue;
// 错误返回
		if (res < 0)
			return res;
		if (FD_ISSET(ctrl->s, &rfds)) {
// 读取数据
			res = recv(ctrl->s, reply, *reply_len, 0);
			if (res < 0)
				return res;
			if ((res > 0 && reply[0] == '<') ||
			    (res > 6 && strncmp(reply, "IFNAME=", 7) == 0)) {
				/* This is an unsolicited message from
				 * wpa_supplicant, not the reply to the
				 * request. Use msg_cb to report this to the
				 * caller. */
// 返回'<'和'IFNAME='时,调用回调函数
				if (msg_cb) {
					/* Make sure the message is nul
					 * terminated. */
					if ((size_t) res == *reply_len)
						res = (*reply_len) - 1;
					reply[res] = '\0';
					msg_cb(reply, res);
				}
				continue;
			}
			*reply_len = res;
			break;
		} else {
			return -2;
		}
	}
	return 0;
}
#endif /* CTRL_IFACE_SOCKET */
```

### 通信过程

- wpa_cli发送SELECT NETWORK

```
static const struct wpa_cli_cmd wpa_cli_commands[] = {

	{ "select_network", wpa_cli_cmd_select_network,
	  wpa_cli_complete_network_id,
	  cli_cmd_flag_none,
	  "<network id> = select a network (disable others)" },
	{ "enable_network", wpa_cli_cmd_enable_network,
	  wpa_cli_complete_network_id,
	  cli_cmd_flag_none,
	  "<network id> = enable a network" },


static int wpa_cli_cmd_select_network(struct wpa_ctrl *ctrl, int argc,
				      char *argv[])
{
	return wpa_cli_cmd(ctrl, "SELECT_NETWORK", 1, argc, argv);
}

static int wpa_cli_cmd(struct wpa_ctrl *ctrl, const char *cmd, int min_args,
		       int argc, char *argv[])
{
	char buf[4096];
	if (argc < min_args) {
		printf("Invalid %s command - at least %d argument%s "
		       "required.\n", cmd, min_args,
		       min_args > 1 ? "s are" : " is");
		return -1;
	}
	if (write_cmd(buf, sizeof(buf), cmd, argc, argv) < 0)
		return -1;
	return wpa_ctrl_command(ctrl, buf);
}

static int wpa_ctrl_command(struct wpa_ctrl *ctrl, const char *cmd)
{
	return _wpa_ctrl_command(ctrl, cmd, 1);
}


static int _wpa_ctrl_command(struct wpa_ctrl *ctrl, const char *cmd, int print)
{
	char buf[4096];
	size_t len;
	int ret;

	if (ctrl_conn == NULL) {
		printf("Not connected to wpa_supplicant - command dropped.\n");
		return -1;
	}
	if (ifname_prefix) {
		os_snprintf(buf, sizeof(buf), "IFNAME=%s %s",
			    ifname_prefix, cmd);
		buf[sizeof(buf) - 1] = '\0';
		cmd = buf;
	}
	len = sizeof(buf) - 1;
	ret = wpa_ctrl_request(ctrl, cmd, os_strlen(cmd), buf, &len,
			       wpa_cli_msg_cb);
	if (ret == -2) {
		printf("'%s' command timed out.\n", cmd);
		return -2;
	} else if (ret < 0) {
		printf("'%s' command failed.\n", cmd);
		return -1;
	}
	if (print) {
		buf[len] = '\0';
		printf("%s", buf);
		if (interactive && len > 0 && buf[len - 1] != '\n')
			printf("\n");
	}
	return 0;
}
```
 
- wpa_supplicant接受数据并返回

  wpa_supplicant里面eloop注册，监听socket。接收wpa_cli的数据进行数据

  eloop_register_read_sock(priv->sock, wpa_supplicant_ctrl_iface_receive);

ctrl_iface_udp.c
```
static void wpa_supplicant_ctrl_iface_receive(int sock, void *eloop_ctx,
					      void *sock_ctx)
{
	struct wpa_supplicant *wpa_s = eloop_ctx;
	struct ctrl_iface_priv *priv = sock_ctx;
	char *buf, *pos;
	int res;
#ifdef CONFIG_CTRL_IFACE_UDP_IPV6
	struct sockaddr_in6 from;
#ifndef CONFIG_CTRL_IFACE_UDP_REMOTE
	char addr[INET6_ADDRSTRLEN];
#endif /* CONFIG_CTRL_IFACE_UDP_REMOTE */
#else /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	struct sockaddr_in from;
#endif /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	socklen_t fromlen = sizeof(from);
	char *reply = NULL;
	size_t reply_len = 0;
	int new_attached = 0;
	u8 cookie[COOKIE_LEN];

	buf = os_malloc(CTRL_IFACE_MAX_LEN + 1);
	if (!buf)
		return;
// 接收数据，地址保存在from中
	res = recvfrom(sock, buf, CTRL_IFACE_MAX_LEN, 0,
		       (struct sockaddr *) &from, &fromlen);
	if (res < 0) {
		wpa_printf(MSG_ERROR, "recvfrom(ctrl_iface): %s",
			   strerror(errno));
		os_free(buf);
		return;
	}

#ifndef CONFIG_CTRL_IFACE_UDP_REMOTE
#ifdef CONFIG_CTRL_IFACE_UDP_IPV6
	inet_ntop(AF_INET6, &from.sin6_addr, addr, sizeof(from));
	if (os_strcmp(addr, "::1")) {
		wpa_printf(MSG_DEBUG, "CTRL: Drop packet from unexpected source %s",
			   addr);
		os_free(buf);
		return;
	}
#else /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	if (from.sin_addr.s_addr != htonl((127 << 24) | 1)) {
		/*
		 * The OS networking stack is expected to drop this kind of
		 * frames since the socket is bound to only localhost address.
		 * Just in case, drop the frame if it is coming from any other
		 * address.
		 */
		wpa_printf(MSG_DEBUG, "CTRL: Drop packet from unexpected "
			   "source %s", inet_ntoa(from.sin_addr));
		os_free(buf);
		return;
	}
#endif /* CONFIG_CTRL_IFACE_UDP_IPV6 */
#endif /* CONFIG_CTRL_IFACE_UDP_REMOTE */

	if ((size_t) res > CTRL_IFACE_MAX_LEN) {
		wpa_printf(MSG_ERROR, "recvform(ctrl_iface): input truncated");
		os_free(buf);
		return;
	}
	buf[res] = '\0';
// 处理GET_COOKIE
	if (os_strcmp(buf, "GET_COOKIE") == 0) {
		reply = wpa_supplicant_ctrl_iface_get_cookie(priv, &reply_len);
		goto done;
	}

	/*
	 * Require that the client includes a prefix with the 'cookie' value
	 * fetched with GET_COOKIE command. This is used to verify that the
	 * client has access to a bidirectional link over UDP in order to
	 * avoid attacks using forged localhost IP address even if the OS does
	 * not block such frames from remote destinations.
	 */
	if (os_strncmp(buf, "COOKIE=", 7) != 0) {
		wpa_printf(MSG_DEBUG, "CTLR: No cookie in the request - "
			   "drop request");
		os_free(buf);
		return;
	}

	if (hexstr2bin(buf + 7, cookie, COOKIE_LEN) < 0) {
		wpa_printf(MSG_DEBUG, "CTLR: Invalid cookie format in the "
			   "request - drop request");
		os_free(buf);
		return;
	}

	if (os_memcmp(cookie, priv->cookie, COOKIE_LEN) != 0) {
		wpa_printf(MSG_DEBUG, "CTLR: Invalid cookie in the request - "
			   "drop request");
		os_free(buf);
		return;
	}

	pos = buf + 7 + 2 * COOKIE_LEN;
	while (*pos == ' ')
		pos++;

	if (os_strcmp(pos, "ATTACH") == 0) {
		if (wpa_supplicant_ctrl_iface_attach(&priv->ctrl_dst,
						     &from, fromlen))
			reply_len = 1;
		else {
			new_attached = 1;
			reply_len = 2;
		}
	} else if (os_strcmp(pos, "DETACH") == 0) {
		if (wpa_supplicant_ctrl_iface_detach(&priv->ctrl_dst,
						     &from, fromlen))
			reply_len = 1;
		else
			reply_len = 2;
	} else if (os_strncmp(pos, "LEVEL ", 6) == 0) {
		if (wpa_supplicant_ctrl_iface_level(priv, &from, fromlen,
						    pos + 6))
			reply_len = 1;
		else
			reply_len = 2;
	} else {
// 处理wpa_cli的各种命令
		reply = wpa_supplicant_ctrl_iface_process(wpa_s, pos,
							  &reply_len);
	}

 done:
	if (reply) {
// 返回数据
		sendto(sock, reply, reply_len, 0, (struct sockaddr *) &from,
		       fromlen);
		os_free(reply);
	} else if (reply_len == 1) {
// 返回FAIL
		sendto(sock, "FAIL\n", 5, 0, (struct sockaddr *) &from,
		       fromlen);
	} else if (reply_len == 2) {
// 返回OK
		sendto(sock, "OK\n", 3, 0, (struct sockaddr *) &from,
		       fromlen);
	}

	os_free(buf);

	if (new_attached)
		eapol_sm_notify_ctrl_attached(wpa_s->eapol);

}

// 接口初始化
struct ctrl_iface_priv *
wpa_supplicant_ctrl_iface_init(struct wpa_supplicant *wpa_s)
{
	struct ctrl_iface_priv *priv;
	char port_str[40];
	int port = WPA_CTRL_IFACE_PORT;
	char *pos;
#ifdef CONFIG_CTRL_IFACE_UDP_IPV6
	struct sockaddr_in6 addr;
	int domain = PF_INET6;
#else /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	struct sockaddr_in addr;
	int domain = PF_INET;
#endif /* CONFIG_CTRL_IFACE_UDP_IPV6 */

	priv = os_zalloc(sizeof(*priv));
	if (priv == NULL)
		return NULL;
	priv->wpa_s = wpa_s;
	priv->sock = -1;
	os_get_random(priv->cookie, COOKIE_LEN);

	if (wpa_s->conf->ctrl_interface == NULL)
		return priv;

	pos = os_strstr(wpa_s->conf->ctrl_interface, "udp:");
	if (pos) {
		pos += 4;
		port = atoi(pos);
		if (port <= 0) {
			wpa_printf(MSG_ERROR, "Invalid ctrl_iface UDP port: %s",
				   wpa_s->conf->ctrl_interface);
			goto fail;
		}
	}

	priv->sock = socket(domain, SOCK_DGRAM, 0);
	if (priv->sock < 0) {
		wpa_printf(MSG_ERROR, "socket(PF_INET): %s", strerror(errno));
		goto fail;
	}

	os_memset(&addr, 0, sizeof(addr));
#ifdef CONFIG_CTRL_IFACE_UDP_IPV6
	addr.sin6_family = AF_INET6;
#ifdef CONFIG_CTRL_IFACE_UDP_REMOTE
	addr.sin6_addr = in6addr_any;
#else /* CONFIG_CTRL_IFACE_UDP_REMOTE */
	inet_pton(AF_INET6, "::1", &addr.sin6_addr);
#endif /* CONFIG_CTRL_IFACE_UDP_REMOTE */
#else /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	addr.sin_family = AF_INET;
#ifdef CONFIG_CTRL_IFACE_UDP_REMOTE
	addr.sin_addr.s_addr = INADDR_ANY;
#else /* CONFIG_CTRL_IFACE_UDP_REMOTE */
	addr.sin_addr.s_addr = htonl((127 << 24) | 1);
#endif /* CONFIG_CTRL_IFACE_UDP_REMOTE */
#endif /* CONFIG_CTRL_IFACE_UDP_IPV6 */
try_again:
#ifdef CONFIG_CTRL_IFACE_UDP_IPV6
	addr.sin6_port = htons(port);
#else /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	addr.sin_port = htons(port);
#endif /* CONFIG_CTRL_IFACE_UDP_IPV6 */
	if (bind(priv->sock, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
		port--;
		if ((WPA_CTRL_IFACE_PORT - port) < WPA_CTRL_IFACE_PORT_LIMIT)
			goto try_again;
		wpa_printf(MSG_ERROR, "bind(AF_INET): %s", strerror(errno));
		goto fail;
	}

	/* Update the ctrl_interface value to match the selected port */
	os_snprintf(port_str, sizeof(port_str), "udp:%d", port);
	os_free(wpa_s->conf->ctrl_interface);
	wpa_s->conf->ctrl_interface = os_strdup(port_str);
	if (!wpa_s->conf->ctrl_interface) {
		wpa_msg(wpa_s, MSG_ERROR, "Failed to malloc ctrl_interface");
		goto fail;
	}

#ifdef CONFIG_CTRL_IFACE_UDP_REMOTE
	wpa_msg(wpa_s, MSG_DEBUG, "ctrl_iface_init UDP port: %d", port);
#endif /* CONFIG_CTRL_IFACE_UDP_REMOTE */
	// 回调函数注册
	eloop_register_read_sock(priv->sock, wpa_supplicant_ctrl_iface_receive,
				 wpa_s, priv);
	wpa_msg_register_cb(wpa_supplicant_ctrl_iface_msg_cb);

	return priv;

fail:
	if (priv->sock >= 0)
		close(priv->sock);
	os_free(priv);
	return NULL;
}
```

ctrl_iface.c

```

// 处理wpa_cli发送过来的命令
char * wpa_supplicant_ctrl_iface_process(struct wpa_supplicant *wpa_s,
					 char *buf, size_t *resp_len)
{
	char *reply;
	const int reply_size = 4096;
	int reply_len;


	} else if (os_strncmp(buf, "SELECT_NETWORK ", 15) == 0) {
		if (wpa_supplicant_ctrl_iface_select_network(wpa_s, buf + 15))
			reply_len = -1;
	} else if (os_strncmp(buf, "ENABLE_NETWORK ", 15) == 0) {
		if (wpa_supplicant_ctrl_iface_enable_network(wpa_s, buf + 15))
			reply_len = -1;
	} else if (os_strncmp(buf, "DISABLE_NETWORK ", 16) == 0) {
		if (wpa_supplicant_ctrl_iface_disable_network(wpa_s, buf + 16))
			reply_len = -1;
	} else if (os_strcmp(buf, "ADD_NETWORK") == 0) {
		reply_len = wpa_supplicant_ctrl_iface_add_network(
			wpa_s, reply, reply_size);
	} else if (os_strncmp(buf, "REMOVE_NETWORK ", 15) == 0) {
		if (wpa_supplicant_ctrl_iface_remove_network(wpa_s, buf + 15))
			reply_len = -1;
	} else if (os_strncmp(buf, "SET_NETWORK ", 12) == 0) {
		if (wpa_supplicant_ctrl_iface_set_network(wpa_s, buf + 12))
			reply_len = -1;

......


	if (reply_len < 0) {
		os_memcpy(reply, "FAIL\n", 5);
		reply_len = 5;
	}

	*resp_len = reply_len;
	return reply;

```
