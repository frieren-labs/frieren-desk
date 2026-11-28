---
---
/* Enchantments: copy buttons, a smooth draggable chibi mascot with a
   mini chat, background music toggle, back to top. The particle overlay
   was removed. Motion is skipped when the reader prefers reduced motion. */
(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  document.querySelectorAll(".copy-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var target = document.getElementById(btn.getAttribute("data-copy"));
      if (!target) return;
      var text = target.innerText;
      function done() {
        btn.textContent = "copied";
        setTimeout(function () { btn.textContent = "copy"; }, 1600);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, done);
      } else {
        var ta = document.createElement("textarea");
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); } catch (e) { /* ignore */ }
        document.body.removeChild(ta);
        done();
      }
    });
  });

  function loop() {
    placeMascot();
    if (!dragging && !chatOpen && !reduced) wanderMascot();
    requestAnimationFrame(loop);
  }

  /* Mascot: wanders on her own, accepts drags, and answers fixed
     questions through a mini chat. Positioned with transform so
     dragging stays smooth. */

  var POSES = {
    idle: "{{ '/assets/img/poses/idle.png' | relative_url }}",
    think: "{{ '/assets/img/poses/think.png' | relative_url }}",
    talk: "{{ '/assets/img/poses/talk.png' | relative_url }}",
    listen: "{{ '/assets/img/poses/listen.png' | relative_url }}",
    greet: "{{ '/assets/img/poses/greet.png' | relative_url }}",
    walk1: "{{ '/assets/img/poses/walk-1.png' | relative_url }}",
    walk2: "{{ '/assets/img/poses/walk-2.png' | relative_url }}",
    cast: "{{ '/assets/img/poses/cast.png' | relative_url }}",
    happy: "{{ '/assets/img/poses/happy.png' | relative_url }}",
    celebrate: "{{ '/assets/img/poses/celebrate.png' | relative_url }}",
    reading: "{{ '/assets/img/poses/reading.png' | relative_url }}"
  };
  var walkFrame = false;
  var QA = [
    {
      q: "How do I install?",
      pose: "cast",
      a: "One spell: <code>curl ... | bash</code>, then hook Hyprland. Full ritual in <a href=\"#install\">Summon</a>."
    },
    {
      q: "What can she do?",
      pose: "happy",
      a: "She chats through opencode, runs commands and edits files, reacting pose by pose. See <a href=\"#how-it-works\">Spellbook</a>."
    },
    {
      q: "Which mood is which?",
      pose: "celebrate",
      a: "think is reasoning, cast is a running tool, sad is an error, sleep is idle. Full table in <a href=\"#poses\">Moods</a>."
    },
    {
      q: "Is it safe?",
      pose: "think",
      a: "The agent refuses sudo, rm -rf /, secret reads and piped shells. Keys travel over stdin only. Details in <a href=\"#safety\">Wardings</a>."
    },
    {
      q: "Which helpers exist?",
      pose: "reading",
      a: "frieren-stats, frieren-ask, frieren-shot, frieren-backup, frieren-voice, frieren-weekly. See <a href=\"#helpers\">Artifacts</a>."
    },
    {
      q: "Does she talk?",
      pose: "talk",
      a: "Yes, voice replies through Piper or espeak, plus UI sounds. Tune it from <a href=\"#controls\">Controls</a>."
    }
  ];

  var chatOpen = false;
  var mascot = document.createElement("div");
  mascot.id = "mascot";
  var face = document.createElement("img");
  face.alt = "Chibi Frieren, click to chat, drag to move";
  face.src = POSES.idle;
  mascot.appendChild(face);
  document.body.appendChild(mascot);

  var panel = document.createElement("div");
  panel.id = "mascot-chat";
  panel.setAttribute("role", "dialog");
  panel.setAttribute("aria-label", "Ask Frieren");
  var head = document.createElement("div");
  head.className = "chat-head";
  var title = document.createElement("strong");
  title.textContent = "Ask Frieren";
  var close = document.createElement("button");
  close.className = "chat-close";
  close.setAttribute("aria-label", "Close chat");
  close.textContent = "x";
  head.appendChild(title);
  head.appendChild(close);
  panel.appendChild(head);
  var answer = document.createElement("p");
  answer.className = "a";
  answer.textContent = "Pick a question...";
  QA.forEach(function (item) {
    var b = document.createElement("button");
    b.className = "q";
    b.textContent = item.q;
    b.addEventListener("click", function () {
      panel.querySelectorAll(".q").forEach(function (o) { o.classList.remove("active"); });
      b.classList.add("active");
      face.src = POSES[item.pose];
      answer.innerHTML = item.a;
    });
    panel.appendChild(b);
  });
  panel.appendChild(answer);
  document.body.appendChild(panel);

  function openChat() {
    chatOpen = true;
    panel.classList.add("open");
    face.src = POSES.listen;
  }
  function closeChat() {
    chatOpen = false;
    panel.classList.remove("open");
    face.src = POSES.idle;
    panel.querySelectorAll(".q").forEach(function (o) { o.classList.remove("active"); });
    answer.textContent = "Pick a question...";
  }
  close.addEventListener("click", closeChat);
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && chatOpen) closeChat();
  });

  var pos = {
    x: window.innerWidth - 160,
    y: window.innerHeight - 220,
    tx: window.innerWidth - 160,
    ty: window.innerHeight - 220,
    waitUntil: 0
  };
  var dragging = false;

  function placeMascot() {
    mascot.style.transform = "translate3d(" + pos.x + "px," + pos.y + "px,0)";
  }

  function pickTarget() {
    var m = 70;
    pos.tx = m + Math.random() * Math.max(window.innerWidth - m * 2 - 96, m);
    pos.ty = m + Math.random() * Math.max(window.innerHeight - m * 2 - 120, m);
  }

  function wanderMascot() {
    var now = performance.now();
    if (now < pos.waitUntil) return;
    var dx = pos.tx - pos.x;
    var dy = pos.ty - pos.y;
    var dist = Math.sqrt(dx * dx + dy * dy);
    if (dist < 4) {
      pos.waitUntil = now + 2500 + Math.random() * 4000;
      pickTarget();
      if (!chatOpen && !dragging) face.src = POSES.idle;
      return;
    }
    var step = Math.min(dist, 1.1);
    pos.x += (dx / dist) * step;
    pos.y += (dy / dist) * step;
    walkFrame = !walkFrame;
    if (!chatOpen && !dragging) face.src = walkFrame ? POSES.walk2 : POSES.walk1;
  }

  var grabDX = 0;
  var grabDY = 0;
  var downX = 0;
  var downY = 0;
  var revertTimer = null;

  mascot.addEventListener("pointerdown", function (e) {
    dragging = true;
    downX = e.clientX;
    downY = e.clientY;
    grabDX = e.clientX - pos.x;
    grabDY = e.clientY - pos.y;
    mascot.classList.add("dragging");
    try { mascot.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
    face.src = POSES.cast;
    if (revertTimer) clearTimeout(revertTimer);
  });

  mascot.addEventListener("pointermove", function (e) {
    if (!dragging) return;
    pos.x = Math.min(Math.max(e.clientX - grabDX, 0), window.innerWidth - 96);
    pos.y = Math.min(Math.max(e.clientY - grabDY, 0), window.innerHeight - 110);
    pos.tx = pos.x;
    pos.ty = pos.y;
    placeMascot();
  });

  function endDrag(e) {
    if (!dragging) return;
    dragging = false;
    mascot.classList.remove("dragging");
    var moved = Math.abs(e.clientX - downX) + Math.abs(e.clientY - downY);
    if (moved < 6) {
      if (chatOpen) closeChat();
      else openChat();
      return;
    }
    face.src = POSES.happy;
    if (revertTimer) clearTimeout(revertTimer);
    revertTimer = setTimeout(function () {
      if (!chatOpen) face.src = POSES.idle;
      pos.waitUntil = performance.now() + 1500;
      pickTarget();
    }, 1700);
  }
  mascot.addEventListener("pointerup", endDrag);
  mascot.addEventListener("pointercancel", endDrag);

  /* Background music: a local mp3, off by default, toggled from the header. */

  var bgm = document.getElementById("bg-music");
  var musicBtn = document.getElementById("music-toggle");
  bgm.volume = 0.8;
  function persistMusic() {
    try {
      localStorage.setItem("frieren-pages-music", bgm.paused ? "off" : "on");
    } catch (e) { /* ignore */ }
  }
  bgm.addEventListener("play", function () {
    musicBtn.setAttribute("aria-pressed", "true");
    persistMusic();
  });
  bgm.addEventListener("pause", function () {
    musicBtn.setAttribute("aria-pressed", "false");
    persistMusic();
  });
  musicBtn.addEventListener("click", function () {
    if (bgm.paused) {
      var p = bgm.play();
      if (p && p.catch) p.catch(function () { /* autoplay blocked, stays off */ });
    } else {
      bgm.pause();
    }
  });
  try {
    if (localStorage.getItem("frieren-pages-music") === "on") {
      var arm = function () {
        document.removeEventListener("pointerdown", arm);
        if (bgm.paused) {
          var p = bgm.play();
          if (p && p.catch) p.catch(function () { /* ignore */ });
        }
      };
      document.addEventListener("pointerdown", arm);
    }
  } catch (e) { /* ignore */ }

  /* Back to top plus scroll-driven backdrop crossfade */

  var toTop = document.getElementById("to-top");
  var bgVideos = Array.prototype.slice.call(document.querySelectorAll(".bg-video"));
  var bgTicking = false;

  if (!reduced) {
    Array.prototype.slice.call(document.querySelectorAll(".hero-video")).forEach(function (v) {
      var pr = v.play();
      if (pr && pr.catch) pr.catch(function () { /* ignore */ });
    });
  }

  function paintScroll() {
    bgTicking = false;
    if (!reduced) {
      var max = document.documentElement.scrollHeight - window.innerHeight;
      var p = max > 0 ? window.scrollY / max : 0;
      var n = bgVideos.length;
      bgVideos.forEach(function (v, i) {
        var o = n === 1 ? 1 : Math.max(0, 1 - Math.abs(p * (n - 1) - i));
        v.style.opacity = o.toFixed(3);
        if (o > 0.05) {
          var pr = v.play();
          if (pr && pr.catch) pr.catch(function () { /* ignore */ });
        } else {
          v.pause();
        }
      });
    }
    if (window.scrollY > 600) toTop.classList.add("show");
    else toTop.classList.remove("show");
  }
  window.addEventListener("scroll", function () {
    if (!bgTicking) {
      bgTicking = true;
      requestAnimationFrame(paintScroll);
    }
  }, { passive: true });
  paintScroll();
  toTop.addEventListener("click", function () {
    window.scrollTo({ top: 0, behavior: reduced ? "auto" : "smooth" });
  });

  pickTarget();
  placeMascot();
  requestAnimationFrame(loop);
})();
