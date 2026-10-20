import 'package:flutter/material.dart';

import '../services/ai_configuration.dart';
import 'editors.dart';

class AiSettings extends StatelessWidget {
  const AiSettings({super.key});
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(Icons.key_outlined),
      title: const Text('API trích từ vựng'),
      subtitle: const Text(
        'OpenAI / Azure OpenAI · key lưu riêng trên thiết bị',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const AiSettingsPage()),
      ),
    ),
  );
}

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});
  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _ConfigFields {
  AiProvider provider = AiProvider.openai;
  final key = TextEditingController(),
      model = TextEditingController(),
      endpoint = TextEditingController();
  final context = TextEditingController(text: '16384');
  bool structured = true;
  void load(AiConfiguration c) {
    provider = c.provider;
    key.text = c.key;
    model.text = c.model;
    endpoint.text = c.endpoint;
    context.text = '${c.contextWindow}';
    structured = c.structured;
  }

  AiConfiguration value() => AiConfiguration(
    provider: provider,
    key: key.text.trim(),
    model: model.text.trim(),
    endpoint: endpoint.text.trim(),
    structured: structured,
    contextWindow: int.tryParse(context.text) ?? 0,
  );
  void dispose() {
    key.dispose();
    model.dispose();
    endpoint.dispose();
    context.dispose();
  }
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final _primary = _ConfigFields(), _fallback = _ConfigFields();
  final _store = const AiConfigurationStore();
  bool _fallbackEnabled = false, _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await _store.load();
      if (!mounted) return;
      if (prefs != null) {
        _primary.load(prefs.primary);
        if (prefs.fallback != null) {
          _fallback.load(prefs.fallback!);
          _fallbackEnabled = true;
        }
      }
    } catch (e) {
      if (mounted) _error = friendlyError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _primary.dispose();
    _fallback.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (clear) {
        await _store.clear();
      } else {
        await _store.save(
          AiPreferences(
            _primary.value(),
            _fallbackEnabled ? _fallback.value() : null,
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clear
                  ? 'Đã xóa cấu hình API.'
                  : 'Đã lưu API. Chưa gọi mạng hoặc tính phí.',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _busy = false;
        });
      }
    }
  }

  Widget _fields(_ConfigFields fields, String title) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<AiProvider>(
            initialValue: fields.provider,
            decoration: const InputDecoration(labelText: 'Dịch vụ'),
            items: const [
              DropdownMenuItem(value: AiProvider.openai, child: Text('OpenAI')),
              DropdownMenuItem(
                value: AiProvider.azure,
                child: Text('Azure OpenAI (API v1)'),
              ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => fields.provider = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: fields.key,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'API key'),
            maxLength: 4096,
          ),
          TextField(
            controller: fields.model,
            enabled: !_busy,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: fields.provider == AiProvider.azure
                  ? 'Tên deployment'
                  : 'Tên model',
              helperText: 'Dùng model hỗ trợ Chat Completions và JSON; đối chiếu quyền trong tài khoản.',
            ),
            maxLength: 200,
          ),
          if (fields.provider == AiProvider.azure) ...[
            const SizedBox(height: 12),
            TextField(
              controller: fields.endpoint,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Azure endpoint',
                hintText: 'https://TEN.openai.azure.com',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: fields.context,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Context window của model (tokens)',
              helperText: 'App dành tối đa 2.500 output tokens.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: fields.structured,
            onChanged: _busy
                ? null
                : (v) => setState(() => fields.structured = v),
            title: const Text('Structured Outputs'),
            subtitle: const Text(
              'Tắt nếu model chỉ hỗ trợ JSON mode. App luôn kiểm tra kết quả lại.',
            ),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Cấu hình API')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Key dùng cho tài khoản của bạn, lưu bằng kho bảo mật hệ điều hành. Không kèm trong backup hoặc gửi lên GitHub. Passage chỉ gửi khi bạn bấm Trích từ, tới dịch vụ đã chọn và dự phòng nếu bật.',
              ),
              const SizedBox(height: 16),
              _fields(_primary, 'Dịch vụ chính'),
              SwitchListTile(
                value: _fallbackEnabled,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _fallbackEnabled = v),
                title: const Text('Cho phép dịch vụ dự phòng'),
                subtitle: const Text(
                  'Tổng tối đa 3 HTTP attempts/job. Từ chối nội dung hoặc hủy sẽ không chuyển dịch vụ.',
                ),
              ),
              if (_fallbackEnabled) _fields(_fallback, 'Dịch vụ dự phòng'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Đang xử lý…' : 'Lưu cấu hình'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _save(clear: true),
                child: const Text('Xóa cấu hình và key trên thiết bị'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
