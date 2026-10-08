namespace NaturalKana.Windows.Core;

public enum Diagnostic
{
    Configuration, MissingKey, InvalidModelId, ModelUnavailable, UnsupportedParameter,
    Network, Timeout, InvalidResponse, Truncated, Refused, ProviderQuota, Quota, HttpStatus, Unavailable,
}

/// Only fixed messages and numeric HTTP status are shown; provider bodies and keys are never echoed.
public sealed class SuggestionException(Diagnostic kind, int status = 0) : Exception(Describe(kind, status))
{
    public Diagnostic Kind { get; } = kind;
    public int Status { get; } = status;

    public static string Describe(Diagnostic kind, int status = 0) => kind switch
    {
        Diagnostic.Configuration => "请在设置里填写有效的 HTTPS 接口地址和模型 ID",
        Diagnostic.MissingKey => "请在设置里保存所选服务商的 API 密钥",
        Diagnostic.InvalidModelId => "模型 ID 不能含空格；请填写服务商 API 文档中的 ID",
        Diagnostic.ModelUnavailable => "模型不存在或无访问权限，请核对 API 模型 ID",
        Diagnostic.UnsupportedParameter => "模型不支持当前参数；请在设置的“高级”里调整 JSON 格式或输出长度参数",
        Diagnostic.Network => "网络连接失败，请检查网络、代理和接口地址",
        Diagnostic.Timeout => "请求超时（20 秒），请稍后重试；Qwen 可开启非思考模式",
        Diagnostic.InvalidResponse => "服务商已响应，但返回内容不符合候选格式，请重试或换个模型",
        Diagnostic.Truncated => "模型回复被截断；可缩短句子或开启非思考模式",
        Diagnostic.Refused => "服务商拒绝生成此内容",
        Diagnostic.ProviderQuota => "服务商返回余额或额度不足，请检查服务商账户",
        Diagnostic.Quota => "已达到本机今日请求上限（可在设置里调整）",
        Diagnostic.HttpStatus => status switch
        {
            401 => "密钥验证失败（HTTP 401），请检查密钥及接口地区",
            403 => "服务商拒绝访问（HTTP 403），请检查账户和模型权限",
            404 => "接口或模型不存在（HTTP 404），请检查接口地址和模型 ID",
            429 => "服务商限制了请求（HTTP 429），请稍后重试",
            400 or 422 => $"请求参数被拒绝（HTTP {status}），请检查模型是否支持 JSON Schema 等参数",
            >= 500 => $"服务商暂时出错（HTTP {status}），请稍后重试",
            _ => $"服务商请求失败（HTTP {status}），请检查服务商配置",
        },
        _ => "请求未完成，发生了未识别的错误，请重试",
    };
}
