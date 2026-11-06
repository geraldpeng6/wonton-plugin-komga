# shellcheck shell=bash
# Komga：sso=oidc（Spring OAuth2，服务端拿 code 换会话，浏览器链路 curl 跟随重定向即可走完）。
# 页面：Komga SPA 的 index.html。
# 身份：走 OIDC 授权链建立 Komga 会话（SESSION Cookie 落进 JAR），再调应用自己的
#       /api/v2/users/me，断言邮箱是主人且角色含 ADMIN（管理员由 init 认领服务按主人邮箱建好）。
# 数据：给当前用户建一把 API key（comment=wonton-smoke），写进 Komga 的 sqlite；
#       升级/重装后 data_check 断言它还在。

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

identity_check() { # 应用认出的是主人本人且是管理员
  local me
  me="$(komga_me)" || { echo "拿不到当前用户：$me"; return 1; }
  jq -e --arg e "$SMOKE_OWNER_EMAIL" \
    '.email == $e and (.roles | index("ADMIN")) != null' <<<"$me" >/dev/null ||
    { echo "当前用户不是主人管理员（$SMOKE_OWNER_EMAIL）：$me"; return 1; }
}

data_write() { # 建一把 API key，验证创建成功；已存在就不重复建
  local keys
  komga_me >/dev/null || { echo "拿不到当前用户"; return 1; }
  keys="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me/api-keys")" ||
    { echo "列不出 API key"; return 1; }
  if jq -e '.[] | select(.comment == "wonton-smoke")' <<<"$keys" >/dev/null; then
    return 0
  fi
  curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' -b "$SMOKE_JAR" -H 'Content-Type: application/json' \
    -d '{"comment":"wonton-smoke"}' "$SMOKE_WEB_URL/api/v2/users/me/api-keys" | grep -q 200 ||
    { echo "创建 API key 失败"; return 1; }
  keys="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me/api-keys")" ||
    { echo "创建后列不出 API key"; return 1; }
  jq -e '.[] | select(.comment == "wonton-smoke")' <<<"$keys" >/dev/null ||
    { echo "创建后没有 wonton-smoke key：$keys"; return 1; }
}

data_check() { # 升级/重装后 API key 还在（Komga 数据在 /config 的 sqlite 里）
  local keys
  komga_login || { echo "OIDC 登录失败"; return 1; }
  keys="$(curl -sS --noproxy '*' --fail-with-body -b "$SMOKE_JAR" "$SMOKE_WEB_URL/api/v2/users/me/api-keys")" ||
    { echo "列不出 API key"; return 1; }
  jq -e '.[] | select(.comment == "wonton-smoke")' <<<"$keys" >/dev/null ||
    { echo "wonton-smoke key 不在了：$keys"; return 1; }
}
