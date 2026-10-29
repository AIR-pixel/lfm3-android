// 由 scripts/gen-chat-page.py 从 app/lfm3-chat.html 生成，请勿手改
// 内嵌的本地聊天页（由 tools/server 的 "/" 路由直接返回）
static const char * CHAT_PAGE_HTML = R"LFMPAGE(<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>本机模型</title>
<style>
  :root{
    --bg:#15161a; --panel:#1d1f24; --line:#2b2e35;
    --text:#e7e8ea; --dim:#8b9098; --accent:#c8613f; --user:#2a2d34;
  }
  *{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
  html,body{height:100%;margin:0}
  body{
    background:var(--bg);color:var(--text);
    font:15px/1.65 -apple-system,"PingFang SC","Noto Sans CJK SC",sans-serif;
    display:flex;flex-direction:column;
    padding-bottom:env(safe-area-inset-bottom);
  }
  @media (min-width:700px){
    body{max-width:480px;margin:0 auto;border-left:1px solid var(--line);border-right:1px solid var(--line)}
  }
  header{
    display:flex;align-items:center;gap:8px;
    padding:12px 16px;border-bottom:1px solid var(--line);
    font-size:13px;color:var(--dim);flex:0 0 auto;
  }
  .dot{width:7px;height:7px;border-radius:50%;background:#5a5f68;flex:0 0 auto}
  .dot.on{background:#5f9e6a}
  .dot.off{background:#a34a3a}
  #name{flex:1 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text)}
  #stat{flex:0 0 auto;margin-left:auto;font-variant-numeric:tabular-nums}
  #log{flex:1 1 auto;overflow-y:auto;padding:16px;display:flex;flex-direction:column;gap:14px}
  .msg{max-width:88%;white-space:pre-wrap;word-break:break-word}
  .msg.u{align-self:flex-end;background:var(--user);padding:10px 14px;border-radius:14px 14px 3px 14px}
  .msg.a{align-self:flex-start;padding:0 2px}
  .msg.a .think{color:var(--dim);font-size:13px;border-left:2px solid var(--line);padding-left:10px;margin-bottom:8px}
  .msg .meta{font-size:11px;color:var(--dim);margin-top:6px}
  .empty{color:var(--dim);font-size:13px;text-align:center;margin-top:28vh;line-height:2}
  footer{flex:0 0 auto;padding:10px 12px;border-top:1px solid var(--line);background:var(--bg)}
  .row{display:grid;grid-template-columns:minmax(0,1fr) 44px 52px;gap:8px;align-items:end;width:100%}
  textarea{
    min-width:0;width:100%;resize:none;background:var(--panel);color:var(--text);
    border:1px solid var(--line);border-radius:12px;padding:11px 13px;
    font:inherit;max-height:120px;min-height:44px;outline:none;
  }
  textarea:focus{border-color:#3c4048}
  button{
    background:var(--accent);color:#fff;border:0;border-radius:12px;
    width:52px;height:44px;font:inherit;font-weight:500;
  }
  button:disabled{opacity:.45}
  button.ghost{background:transparent;border:1px solid var(--line);color:var(--dim);width:44px;font-size:12px}
</style>
</head>
<body>
<header>
  <span class="dot" id="dot"></span>
  <span id="name">本机模型</span>
  <span id="stat">未连接</span>
</header>
<div id="log"><div class="empty" id="empty">本机推理 · 不联网<br>直接输入问题开始</div></div>
<footer>
  <div class="row">
    <textarea id="inp" rows="1" placeholder="说点什么…"></textarea>
    <button class="ghost" id="clr">清空</button>
    <button id="send">发送</button>
  </div>
</footer>
<script>
// 同源访问（页面由 llama-server 托管）；若从本地文件打开则回退到固定端口
const API = location.protocol === 'http:' ? '' : 'http://127.0.0.1:8080';
const log=document.getElementById('log'), inp=document.getElementById('inp');
const sendBtn=document.getElementById('send'), stat=document.getElementById('stat');
const dot=document.getElementById('dot'), nameEl=document.getElementById('name');
let history=[], busy=false;

const KEY='lfm3-chat-v1';
try{ history=JSON.parse(localStorage.getItem(KEY)||'[]'); }catch(e){ history=[]; }
history.forEach(m=>addMsg(m.role,m.content,m.think,false));
if(history.length) document.getElementById('empty')?.remove();

function addMsg(role,content,think,save=true){
  document.getElementById('empty')?.remove();
  const d=document.createElement('div');
  d.className='msg '+(role==='user'?'u':'a');
  d.textContent=content||'';
  log.appendChild(d);
  log.scrollTop=log.scrollHeight;
  if(save){ history.push({role,content,think}); persist(); }
  return d;
}
function persist(){ try{ localStorage.setItem(KEY,JSON.stringify(history)); }catch(e){} }

// llama-server 的 /v1/models 里 id 就是当前加载的模型路径，用它显示换成了哪个模型
function shortName(id){
  const base=String(id).split(/[\\/]/).pop().replace(/\.gguf$/i,'');
  return base.length>34 ? base.slice(0,33)+'…' : base;
}
async function ping(){
  try{
    const r=await fetch(API+'/v1/models',{signal:AbortSignal.timeout(2500)});
    if(!r.ok) throw new Error(r.status);
    const j=await r.json();
    const id=j&&j.data&&j.data[0]&&j.data[0].id;
    if(id){
      const n=shortName(id);
      nameEl.textContent=n; nameEl.title=id; document.title=n;
    }
    dot.className='dot on'; stat.textContent='已连接';
  }catch(e){
    dot.className='dot off'; stat.textContent='未连接';
  }
}
ping(); setInterval(ping,8000);

async function send(){
  const text=inp.value.trim();
  if(!text||busy) return;
  inp.value=''; inp.style.height='auto';
  addMsg('user',text);
  busy=true; sendBtn.disabled=true;

  const box=document.createElement('div');
  box.className='msg a';
  const thinkEl=document.createElement('div'); thinkEl.className='think'; thinkEl.style.display='none';
  const bodyEl=document.createElement('span');
  const metaEl=document.createElement('div'); metaEl.className='meta';
  box.append(thinkEl,bodyEl,metaEl); log.appendChild(box);

  let think='', raw='', t0=performance.now(), ntok=0;
  const render=()=>{
    const i=raw.indexOf('</think>');
    if(i>=0){
      const t=raw.slice(0,i).replace(/^<think>/,'').trim();
      const b=raw.slice(i+8).replace(/^\s+/,'');
      if(t){ thinkEl.style.display='block'; thinkEl.textContent=t; }
      bodyEl.textContent=b;
    }else{
      bodyEl.textContent=raw.replace(/^<think>/,'');
    }
    log.scrollTop=log.scrollHeight;
  };
  try{
    const r=await fetch(API+'/v1/chat/completions',{
      method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({
        messages:history.filter(m=>m.role!=='system').map(m=>({role:m.role,content:m.content})),
        stream:true, max_tokens:1024, temperature:0.6,
        chat_template_kwargs:{enable_thinking:false}
      })
    });
    if(!r.ok) throw new Error('HTTP '+r.status);
    const rd=r.body.getReader(), dec=new TextDecoder();
    let buf='';
    while(true){
      const {done,value}=await rd.read(); if(done) break;
      buf+=dec.decode(value,{stream:true});
      const lines=buf.split('\n'); buf=lines.pop();
      for(const line of lines){
        const s=line.trim(); if(!s.startsWith('data:')) continue;
        const p=s.slice(5).trim(); if(p==='[DONE]') continue;
        let j; try{ j=JSON.parse(p); }catch(e){ continue; }
        const delta=j.choices?.[0]?.delta||{};
        if(delta.reasoning_content){ think+=delta.reasoning_content; thinkEl.style.display='block'; thinkEl.textContent=think; }
        if(delta.content){ raw+=delta.content; render(); }
        ntok++;
        log.scrollTop=log.scrollHeight;
      }
    }
  }catch(err){
    bodyEl.textContent='请求失败：'+err.message+'（服务是否已启动？）';
  }
  const sec=(performance.now()-t0)/1000;
  if(ntok) metaEl.textContent=(ntok/sec).toFixed(1)+' tok/s · '+ntok+' tokens';
  const clean=bodyEl.textContent;
  history.push({role:'assistant',content:clean,think});
  persist();
  busy=false; sendBtn.disabled=false;
  inp.focus();
}

sendBtn.onclick=send;
inp.addEventListener('keydown',e=>{
  if(e.key==='Enter'&&!e.shiftKey){ e.preventDefault(); send(); }
});
inp.addEventListener('input',()=>{
  inp.style.height='auto'; inp.style.height=Math.min(inp.scrollHeight,120)+'px';
});
document.getElementById('clr').onclick=()=>{
  history=[]; persist(); log.innerHTML='';
  const e=document.createElement('div'); e.className='empty'; e.id='empty';
  e.innerHTML='本机推理 · 不联网<br>直接输入问题开始';
  log.appendChild(e);
};
</script>
</body>
</html>
)LFMPAGE";
