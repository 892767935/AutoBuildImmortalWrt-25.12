'use strict';
'require view';

return view.extend({
	render: function() {
		var host = window.location.hostname;
		var url = 'http://' + host + ':16601';
		return E('div', { 'class': 'cbi-section', 'style': 'max-width:36em; margin:2em auto; text-align:center;' },
			E('h2', {}, 'Lucky'),
			E('p', {}, 'Lucky 拥有独立 Web 管理界面，点击下方按钮打开（新窗口）。'),
			E('p', {},
				E('a', {
					'href': url,
					'target': '_blank',
					'rel': 'noopener',
					'class': 'btn cbi-button-action important'
				}, '打开 Lucky 管理界面')
			),
			E('p', { 'class': 'text-muted' }, '地址：' + url)
		);
	}
});
