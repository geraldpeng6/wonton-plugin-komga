# shellcheck shell=bash
# Komga：sso=oidc（Spring OAuth2，服务端拿 code 换会话，浏览器链路 curl 跟随重定向即可走完）。
# 只用钩子契约里的变量与助手：SMOKE_JAR/SMOKE_WEB_URL/SMOKE_INSTANCE/SMOKE_STATE 和 web_get/dweb。
#
# 身份：走 OIDC 授权链（主人会话 → 核心身份提供方自动登录 → 回调建 Komga 会话），调应用自己的
#       /api/v2/users/me 断言角色含 ADMIN。管理员只有 init 认领服务建的那一个（邮箱=主人邮箱），
#       OIDC 登录能落到 ADMIN 即命中主人账号；若邮箱对不上，Komga 会按邮箱另建普通用户，这里会 FAIL。
# 数据：给当前用户建一把 API key，comment 每次生成唯一值写进 SMOKE_STATE（覆盖写）；
#       data_check 按标记里的 comment 断言 key 还在（Komga 数据在 /config 的 sqlite）。

web_assert() { grep -qi '<title>Komga</title>'; }   # 标准输入：应用真实页面

komga_login() { # 授权起点 → 核心会话自动登录 → 回调换 Komga 会话；重复执行无害
  local start
  start="$(curl -sS --noproxy '*' -o /dev/null -b "$SMOKE_JAR" -c "$SMOKE_JAR" \
    -w '%{redirect_url}' "$SMOKE_WEB_URL/oauth2/authorization/komga")" ||
    { echo "进不了 OIDC 授权起点"; return 1; }
  [[ -n "$start" ]] || { echo "授权起点没有跳到身份提供方"; return 1; }
  curl -sS --noproxy '*' -o /dev/null -L -b "$SMOKE_JAR" -c "$SMOKE_JAR" \
    -H 'Accept: text/html' "$start" || { echo "授权链走不完：$start"; return 1; }
}

komga_me() { # 应用自己的当前用户接口；401 时先走一遍 OIDC 登录再试一次
  local me code
  me="$(curl -sS --noproxy '*' -w '\n%{http_code}' -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me")"
  code="$(tail -1 <<<"$me")"
  if [[ "$code" == 401 || "$code" == 000 ]]; then
    komga_login || return 1
    me="$(curl -sS --noproxy '*' -w '\n%{http_code}' -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me")"
    code="$(tail -1 <<<"$me")"
  fi
  [[ "$code" == 200 ]] || { echo "/api/v2/users/me 返回 $code"; return 1; }
  head -n -1 <<<"$me"
}

komga_marker() { # SMOKE_STATE 按契约是文件；dev.sh probes 那边给的是目录，往里放一个标记文件
  [[ -d "$SMOKE_STATE" ]] && printf '%s/data-marker' "$SMOKE_STATE" || printf '%s' "$SMOKE_STATE"
}

identity_check() { # 应用认出的当前用户是管理员；邮箱作为证据打出来，不断言具体值
  local me
  me="$(komga_me)" || { echo "拿不到当前用户：$me"; return 1; }
  jq -e '(.roles | index("ADMIN")) != null and (.email // "" | length) > 0' <<<"$me" >/dev/null ||
    { echo "OIDC 登录没有落到认领的管理员账号（主人邮箱对不上时 Komga 会另建普通用户）：$me"; return 1; }
  echo "当前用户：$(jq -r .email <<<"$me")"
}

data_write() { # 建一把 API key（comment 唯一），comment 记进 SMOKE_STATE；已建过就沿用
  local keys marker comment
  marker="$(komga_marker)"
  komga_me >/dev/null || { echo "拿不到当前用户"; return 1; }
  comment="$(cat "$marker" 2>/dev/null || true)"
  keys="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me/api-keys")" ||
    { echo "列不出 API key"; return 1; }
  if [[ -n "$comment" ]] && jq -e --arg c "$comment" '.[] | select(.comment == $c)' <<<"$keys" >/dev/null; then
    return 0
  fi
  comment="wonton-smoke-$(date +%s)-$RANDOM"
  curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' -b "$SMOKE_JAR" -H 'Content-Type: application/json' \
    -d "{\"comment\":\"$comment\"}" "$SMOKE_WEB_URL/api/v2/users/me/api-keys" | grep -q 200 ||
    { echo "创建 API key 失败"; return 1; }
  keys="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me/api-keys")" ||
    { echo "创建后列不出 API key"; return 1; }
  jq -e --arg c "$comment" '.[] | select(.comment == $c)' <<<"$keys" >/dev/null ||
    { echo "创建后没有 $comment key：$keys"; return 1; }
  printf '%s' "$comment" >"$marker"
}

data_check() { # 升级/重装后按 SMOKE_STATE 里的 comment 断言 API key 还在
  local keys marker comment
  marker="$(komga_marker)"
  comment="$(cat "$marker" 2>/dev/null || true)"
  [[ -n "$comment" ]] || { echo "SMOKE_STATE 里没有 data_write 写的标记"; return 1; }
  komga_login || { echo "OIDC 登录失败"; return 1; }
  keys="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me/api-keys")" ||
    { echo "列不出 API key"; return 1; }
  jq -e --arg c "$comment" '.[] | select(.comment == $c)' <<<"$keys" >/dev/null ||
    { echo "标记的 key（$comment）不在了：$keys"; return 1; }
}
