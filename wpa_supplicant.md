### wpa_supplicant

```
eloop_init
	eloop_sock_table_dispatch  //处理读，写，异常事件
	
socket事件注册。
nl80211_init_connect_handle
	nl80211_register_eloop_read
		eloop_register_read_sock
			nl_recvmsgs
			

drivers.c
	const struct wpa_driver_ops *const wpa_drivers[] =
	{
	#ifdef CONFIG_DRIVER_NL80211
		&wpa_driver_nl80211_ops,
	#endif /* CONFIG_DRIVER_NL80211 */
	#ifdef CONFIG_DRIVER_WEXT
		&wpa_driver_wext_ops,
	#endif /* CONFIG_DRIVER_WEXT */
	#ifdef CONFIG_DRIVER_HOSTAP
		&wpa_driver_hostap_ops,
	#endif /* CONFIG_DRIVER_HOSTAP */
	
			const struct wpa_driver_ops wpa_driver_nl80211_ops = {
				.name = "nl80211",
				.desc = "Linux nl80211/cfg80211",
				.get_bssid = wpa_driver_nl80211_get_bssid,
				.get_ssid = wpa_driver_nl80211_get_ssid,
				.set_key = driver_nl80211_set_key,
				.scan2 = driver_nl80211_scan2,
				.sched_scan = wpa_driver_nl80211_sched_scan,
				.stop_sched_scan = wpa_driver_nl80211_stop_sched_scan,
				.get_scan_results2 = wpa_driver_nl80211_get_scan_results,
				.abort_scan = wpa_driver_nl80211_abort_scan,
				.deauthenticate = driver_nl80211_deauthenticate,
				.authenticate = driver_nl80211_authenticate,
				.associate = wpa_driver_nl80211_associate,

wpa_supplicant_add_iface
	wpa_supplicant_init_iface
		wpas_init_driver
			wpa_supplicant_set_driver
				select_driver
					名称匹配
		

struct wpa_ssid各种ssid的信息
对应定义defs.h
enum wpa_states {
	/**
	 * WPA_DISCONNECTED - Disconnected state
	 *
	 * This state indicates that client is not associated, but is likely to
	 * start looking for an access point. This state is entered when a
	 * connection is lost.
	 */
	WPA_DISCONNECTED,

	/**
	 * WPA_INTERFACE_DISABLED - Interface disabled
	 *
	 * This state is entered if the network interface is disabled, e.g.,
	 * due to rfkill. wpa_supplicant refuses any new operations that would
	 * use the radio until the interface has been enabled.
	 */
	WPA_INTERFACE_DISABLED,


struct wpa_supplicant {
	struct wpa_global *global;
	
	struct wpa_ssid *current_ssid;
	struct wpa_ssid *last_ssid;
	
	const struct wpa_driver_ops *driver;
					


数据发送接收：
wpa_priv_interface_init
	
	static void wpa_priv_receive
		case PRIVSEP_CMD_REGISTER:
			wpa_priv_cmd_register(iface, &from, fromlen);
			break;
		case PRIVSEP_CMD_UNREGISTER:
			wpa_priv_cmd_unregister(iface, &from);
			break;
		case PRIVSEP_CMD_SCAN:
			wpa_priv_cmd_scan(iface, cmd_buf, cmd_len);
			break;
		case PRIVSEP_CMD_GET_SCAN_RESULTS:
			wpa_priv_cmd_get_scan_results(iface, &from, fromlen);
			break;
		case PRIVSEP_CMD_ASSOCIATE:
			wpa_priv_cmd_associate(iface, cmd_buf, cmd_len);
			break;
		case PRIVSEP_CMD_GET_BSSID:
		
			if (iface->driver->scan2)
				iface->driver->scan2(iface->drv_priv, &params);
					.scan2 = driver_nl80211_scan2,
				
				
状态机初始化：
	wpa_s->eapol = eapol_sm_init(ctx);
	
	
main.c
	case 'i':                      // 接口名称
		iface->ifname = optarg;
	
	wpa_supplicant_init
		wpa_supplicant_global_ctrl_iface_init
			wpas_global_ctrl_iface_open_sock 创建udp本地套接字
			eloop里面select,epoll等方式监听
			eloop_register_read_sock(priv->sock, wpa_supplicant_global_ctrl_iface_receive, global, priv);
				回调函数wpa_supplicant_global_ctrl_iface_receive
							recvfrom()接收数据
							wpa_supplicant_global_ctrl_iface_process
								wpa_supplicant_ctrl_iface_process(wpa_s, buf,  &reply_len);
	wpa_supplicant_add_iface
		wpa_supplicant_init_iface
			wpas_init_driver            // 选择驱动类型，名称匹配，对应wext,nl80211等接口。   supplicant启动是-D参数指定， -Dnl80211, -Dwext
			wpa_supplicant_ctrl_iface_init       // udp socket
				eloop_register_read_sock(priv->sock, wpa_supplicant_ctrl_iface_receive, wpa_s, priv);
					wpa_supplicant_ctrl_iface_process
						} else if (os_strcmp(buf, "SCAN") == 0) {
							wpas_ctrl_scan(wpa_s, NULL, reply, reply_size, &reply_len);
						} else if (os_strncmp(buf, "SCAN ", 5) == 0) {
							wpas_ctrl_scan(wpa_s, buf + 5, reply, reply_size, &reply_len);
						} else if (os_strcmp(buf, "SCAN_RESULTS") == 0) {
							reply_len = wpa_supplicant_ctrl_iface_scan_results(
						
				wpa_msg_register_cb(wpa_supplicant_ctrl_iface_msg_cb);
					
				
			
	
	
wpa_supplicant_init_wpa
	wpa_s->ptksa = ptksa_cache_init();                        // ptk station ap
	ctx->ctx = wpa_s;
	ctx->msg_ctx = wpa_s;
	ctx->set_state = _wpa_supplicant_set_state;
	ctx->get_state = _wpa_supplicant_get_state;
	ctx->deauthenticate = _wpa_supplicant_deauthenticate;
	ctx->reconnect = _wpa_supplicant_reconnect;
	ctx->set_key = wpa_supplicant_set_key;
	ctx->get_network_ctx = wpa_supplicant_get_network_ctx;
	ctx->get_bssid = wpa_supplicant_get_bssid;
	ctx->ether_send = _wpa_ether_send;
	ctx->get_beacon_ie = wpa_supplicant_get_beacon_ie;
	ctx->alloc_eapol = _wpa_alloc_eapol;
	ctx->cancel_auth_timeout = _wpa_supplicant_cancel_auth_timeout;
	ctx->add_pmkid = wpa_supplicant_add_pmkid;
	
	wpa_s->wpa = wpa_sm_init(ctx);             // 状态机初始化
	

	
// netlink发送接收函数
send_and_recv_msgs

// 本地套接字创建
wpas_ctrl_iface_open_sock
		eloop_register_read_sock(priv->sock, wpa_supplicant_ctrl_iface_receive, wpa_s, priv);
		wpa_msg_register_cb(wpa_supplicant_ctrl_iface_msg_cb);
		wpa_supplicant_ctrl_iface_receive
			wpa_supplicant_ctrl_iface_process
				} else if (os_strncmp(buf, "STATUS", 6) == 0) {
					reply_len = wpa_supplicant_ctrl_iface_status(
						wpa_s, buf + 6, reply, reply_size);
				} else if (os_strcmp(buf, "PMKSA") == 0) {
					reply_len = wpas_ctrl_iface_pmksa(wpa_s, reply, reply_size);
				} else if (os_strcmp(buf, "PMKSA_FLUSH") == 0) {
					wpas_ctrl_iface_pmksa_flush(wpa_s);

读取配置文件
wpa_config_read


struct wpa_supplicant {
	void *drv_priv; /* private data used by driver_ops */         // 私有数据
	const struct wpa_driver_ops *driver;            // driver操作接口
	struct wpa_config *conf;                  // config文件
	
// 根据名称，选择对应的driver_ops接口
if (wpa_supplicant_set_driver(wpa_s, driver) < 0)
		wpa_s->driver = wpa_drivers[i]
// 获取driver_ops里面用到的私有数据
wpa_s->drv_priv = wpa_drv_init(wpa_s, wpa_s->ifname);
	wpa_s->driver->init2(wpa_s, ifname, wpa_s->global_drv_priv);
		bss = drv->first_bss;
		bss->drv = drv;		// 保存到bss->drv指向的指针中

get ssid举例，直接将私有数据保存的ssid给传入的变量。
	static int wpa_driver_nl80211_get_ssid(void *priv, u8 *ssid)
	{
		struct i802_bss *bss = priv;
		struct wpa_driver_nl80211_data *drv = bss->drv;
		if (!drv->associated)
			return -1;
		os_memcpy(ssid, drv->ssid, drv->ssid_len);
		return drv->ssid_len;
	}
	

私有数据结构体
wpa_driver_nl80211_data

事件分发
wpa_supplicant_event
	case EVENT_AUTH:
	case EVENT_ASSOC:
case EVENT_DISASSOC:
```
