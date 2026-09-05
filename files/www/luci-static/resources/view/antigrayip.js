'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require poll';
'require ui';
'require network';

var callFileRead = rpc.declare({
	object: 'file',
	method: 'read',
	params: [ 'path' ],
	expect: { data: '' }
});

// Lightweight EN/RU switch that follows LuCI's current UI language, without
// needing a compiled .lmo translation catalog (this app ships as a single
// installer script, outside the opkg build chain).
var LANG = ((document.documentElement.getAttribute('lang') || 'en') + '').substr(0, 2).toLowerCase();
function T(en, ru) {
	return LANG === 'ru' ? ru : en;
}

return view.extend({
	load: function () {
		return Promise.all([
			uci.load('antigrayip'),
			network.getNetworks()
		]);
	},

	render: function (data) {
		var nets = data[1];
		var m, s, o;

		m = new form.Map('antigrayip', 'AntiGrayIP',
			T(
				'Watches the WAN IP address and restarts the WAN interface while the ISP ' +
				'assigns a private/CGNAT ("gray") address, until a public ("white") IP is obtained.',
				'Следит за IP-адресом на WAN и перезапускает интерфейс, пока провайдер выдаёт ' +
				'приватный/CGNAT ("серый") адрес — до получения публичного ("белого") IP.'
			));

		s = m.section(form.NamedSection, 'settings', 'antigrayip', T('Settings', 'Настройки'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', T('Enabled', 'Включено'));
		o.rmempty = false;

		o = s.option(form.MultiValue, 'interface', T('WAN interfaces', 'WAN-интерфейсы'),
			T('Select one or more logical interfaces to monitor — useful when the router has ' +
			  'two or more WAN ports/interfaces (dual-WAN, failover). Each is checked and ' +
			  'reconnected independently.',
			  'Выберите один или несколько логических интерфейсов для мониторинга — актуально, ' +
			  'если на роутере два и более WAN-портов/интерфейсов (dual-WAN, резервирование). ' +
			  'Каждый проверяется и переподключается независимо от остальных.'));
		o.rmempty = false;
		nets.forEach(function (net) {
			var dev = net.getDevice();
			var label = net.getName() + (dev ? ' (' + dev.getName() + ')' : '');
			o.value(net.getName(), label);
		});
		// keep whatever is already saved selectable even if it disappeared
		// from the current network config (e.g. device renamed)
		var saved = uci.get('antigrayip', 'settings', 'interface');
		var savedList = Array.isArray(saved) ? saved : (saved ? [ saved ] : []);
		savedList.forEach(function (v) {
			if (!nets.some(function (n) { return n.getName() === v; })) {
				o.value(v, v + ' ' + T('(not found)', '(не найден)'));
			}
		});

		o = s.option(form.Value, 'interval', T('Check interval (s)', 'Интервал проверки (с)'));
		o.datatype = 'uinteger';
		o.placeholder = '30';

		o = s.option(form.Value, 'retry_delay', T('Delay after each reconnect (s)', 'Пауза после переподключения (с)'));
		o.datatype = 'uinteger';
		o.placeholder = '10';

		o = s.option(form.Value, 'max_retries', T('Log a warning after N failed attempts', 'Писать предупреждение после N неудач подряд'));
		o.datatype = 'uinteger';
		o.placeholder = '5';

		o = s.option(form.Flag, 'escalate_reboot', T('Reboot router if still gray', 'Перезагружать роутер, если IP всё ещё серый'),
			T('Escalate to a full router reboot once the attempt count below is reached',
			  'Перейти к полной перезагрузке роутера по достижении числа попыток ниже'));
		o.rmempty = false;

		o = s.option(form.Value, 'escalate_after', T('Reboot after N failed attempts', 'Перезагружать после N неудач подряд'));
		o.datatype = 'uinteger';
		o.depends('escalate_reboot', '1');
		o.placeholder = '10';

		o = s.option(form.Value, 'log_file', T('Log file', 'Файл журнала'));
		o.placeholder = '/var/log/antigrayip.log';

		o = s.option(form.DynamicList, 'gray_subnet',
			T('Gray / private subnets (CIDR)', 'Серые/приватные подсети (CIDR)'),
			T(
				'Any address inside one of these networks is treated as "gray" and triggers a reconnect. ' +
				'Prefilled with the standard private ranges plus 100.64.0.0/10 — the CGNAT pool Rostelecom ' +
				'actually hands out addresses from. Add, edit or remove entries as needed.',
				'Любой адрес из этих сетей считается "серым" и вызывает переподключение. По умолчанию уже ' +
				'заполнено стандартными приватными диапазонами плюс 100.64.0.0/10 — именно из этого CGNAT-пула ' +
				'Ростелеком выдаёт адреса. Список можно свободно редактировать.'
			));
		o.datatype = 'cidr4';
		o.rmempty = false;

		return m.render().then(L.bind(function (node) {
			var pre = E('pre', {
				'id': 'antigrayip_log',
				'style': 'max-height:320px;overflow:auto;white-space:pre-wrap'
			}, [ T('Loading log…', 'Загрузка журнала…') ]);

			var box = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, T('Recent log', 'Последние записи журнала')),
				pre
			]);

			poll.add(function () {
				return callFileRead('/var/log/antigrayip.log').then(function (data) {
					pre.textContent = data
						? data.trim().split('\n').slice(-40).join('\n')
						: T('(empty)', '(пусто)');
				}).catch(function () {
					pre.textContent = T('(no log yet)', '(журнал ещё не создан)');
				});
			}, 5);

			node.appendChild(box);
			return node;
		}, this));
	}
});
