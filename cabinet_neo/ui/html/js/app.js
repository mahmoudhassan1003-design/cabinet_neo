// cabinet_neo/ui/html/js/app.js — v31
// (+ tall_oven + اختيار القسم السفلي: درجين / درفة / درفتين)
(() => {
  const i18n   = window.CabinetNeoI18n;
  const bridge = window.CabinetNeoBridge;

  const state = {
    tab:      'cabinets',
    lang:     'ar',
    settings: {
      width: 600, height: 780, depth: 580,
      doorType: 'double', shelves: 1, thickness: 18,
      unitSubtype: 'standard',
      ovenDrawer: 'none',
      ovenDrawerBox: true,
      ovenVent: false,
      drawerCount: 3,
      drawerHeights: [230, 230, 230],
      cornerWRight: 900,
      cornerWLeft:  900,
      cornerDRight: 580,
      cornerDLeft:  580,
      fixedSide:    'left',
      counterWidth: 500,
      fillerWidth:  150,
      tallBottomType: 'drawers',  // ⭐ جديد
      tallBottomH: 620,           // ارتفاع القسم السفلي لدولاب الفرن (مم)
      tallOvenH:   600,           // ارتفاع فتحة الفرن (مم)
      tallMicroH:  450,           // ارتفاع درفة الميكروويف (مم)
      // ⭐ دولاب التخزين (كل الأرقام بالمم من الأرض)
      tsLayout:   'door',         // door | drawer_door | two_doors | door_flip
      tsHandles:  false,          // false = بدون مقابض (لمس) / true = بمقابض
      tsDrawerN:  0,              // عدد الأدراج السفلية (0..4)
      tsDrawerH:  250,            // ارتفاع كل درج (مم)
      tsSplitH:   1200,           // ارتفاع الفاصل بين الدرفتين / القلاب
      tsShelves:  4,              // عدد الرفوف
      tsClearH:   0,              // فراغ سفلي بدون رفوف (0 = توزيع عادي)
      tsShelfPos: ''              // مواضع الرفوف يدوي (سم من الأرض، مفصولة بفاصلة)
    },
    activeStyleId: 'modern_white',
    oclMaterials:  null,
    oclSelected:   null,
    stylesList:    null,
    materialsList: null,
    libSearch:     '',
    libFilter:     'all',
    nav:           'library'
  };

  const DOUBLE_DOOR_THRESHOLD = 600;
  const mmToCm = (mm) => Math.round(mm / 10);
  const cmToMm = (cm) => Math.round(cm * 10);

  const $  = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  function showToast(message, type = 'success') {
    let toast = document.getElementById('cnToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'cnToast';
      document.body.appendChild(toast);
    }
    toast.className = 'cn-toast' + (type === 'err' ? ' err' : '');
    toast.textContent = message;
    void toast.offsetWidth;
    toast.classList.add('visible');
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.remove('visible'), 2200);
  }

  const icons = {
    cube:    `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 2 21 7v10l-9 5-9-5V7z"/><path d="M12 12 21 7M12 12 3 7M12 12v10"/></svg>`,
    gear:    `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="3"/></svg>`,
    edit:    `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 20h4l10-10-4-4L4 16z"/></svg>`,
    door:    `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="4" y="3" width="16" height="18" rx="1"/><circle cx="16" cy="12" r=".8" fill="currentColor"/></svg>`,
    shelves: `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 5h16M4 12h16M4 19h16"/></svg>`,
    dimW:    `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M3 12h18M6 8l-3 4 3 4M18 8l3 4-3 4"/></svg>`,
    dimH:    `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 3v18M8 6l4-3 4 3M8 18l4 3 4-3"/></svg>`,
    dimD:    `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M5 5l5 5M19 5l-5 5M5 19l5-5M19 19l-5-5"/></svg>`,
    lock:    `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="5" y="11" width="14" height="9" rx="1.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>`,
    brush:   `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 20s2-1 4-1 3 1 5 1 3-1 3-3c0-3-4-4-6-6S7 6 7 4"/></svg>`,
    plus:    `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>`,
    drawers: `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="3" width="18" height="6" rx="1"/><rect x="3" y="10" width="18" height="6" rx="1"/><rect x="3" y="17" width="18" height="4" rx="1"/></svg>`,
    layers:  `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 2 2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/></svg>`,
    search:  `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.35-4.35"/></svg>`
  };

  const libIcons = {
    doorRight: `<svg viewBox="0 0 60 80" fill="none"><rect x="12" y="6" width="36" height="68" rx="2" stroke="currentColor" stroke-width="2.2"/><circle cx="20" cy="40" r="2" fill="currentColor"/></svg>`,
    doorLeft:  `<svg viewBox="0 0 60 80" fill="none"><rect x="12" y="6" width="36" height="68" rx="2" stroke="currentColor" stroke-width="2.2"/><circle cx="40" cy="40" r="2" fill="currentColor"/></svg>`,
    doorDouble: `<svg viewBox="0 0 60 80" fill="none"><rect x="6" y="6" width="22" height="68" rx="1.5" stroke="currentColor" stroke-width="2.2"/><rect x="32" y="6" width="22" height="68" rx="1.5" stroke="currentColor" stroke-width="2.2"/><circle cx="26" cy="40" r="1.8" fill="currentColor"/><circle cx="34" cy="40" r="1.8" fill="currentColor"/></svg>`,
    drawer2: `<svg viewBox="0 0 60 80" fill="none"><rect x="8" y="8" width="44" height="30" rx="1.5" stroke="currentColor" stroke-width="2.2"/><rect x="8" y="42" width="44" height="30" rx="1.5" stroke="currentColor" stroke-width="2.2"/><path d="M20 23 h20 M20 57 h20" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>`,
    drawer3: `<svg viewBox="0 0 60 80" fill="none"><rect x="8" y="6" width="44" height="20" rx="1.5" stroke="currentColor" stroke-width="2.2"/><rect x="8" y="30" width="44" height="20" rx="1.5" stroke="currentColor" stroke-width="2.2"/><rect x="8" y="54" width="44" height="20" rx="1.5" stroke="currentColor" stroke-width="2.2"/><path d="M20 16 h20 M20 40 h20 M20 64 h20" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`,
    drawerMixed: `<svg viewBox="0 0 60 80" fill="none"><rect x="8" y="6" width="44" height="14" rx="1.5" stroke="currentColor" stroke-width="2.2"/><rect x="8" y="24" width="44" height="24" rx="1.5" stroke="currentColor" stroke-width="2.2"/><rect x="8" y="52" width="44" height="22" rx="1.5" stroke="currentColor" stroke-width="2.2"/><path d="M20 13 h20 M20 36 h20 M20 63 h20" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`,
    oven: `<svg viewBox="0 0 60 80" fill="none"><rect x="6" y="6" width="48" height="68" rx="2" stroke="currentColor" stroke-width="2.2"/><rect x="14" y="14" width="32" height="26" rx="1.5" stroke="currentColor" stroke-width="1.8"/><circle cx="30" cy="56" r="6" stroke="currentColor" stroke-width="1.8"/><path d="M30 50 v12 M24 56 h12" stroke="currentColor" stroke-width="1.2"/></svg>`,
    sink: `<svg viewBox="0 0 60 80" fill="none"><rect x="6" y="6" width="48" height="68" rx="2" stroke="currentColor" stroke-width="2.2"/><path d="M15 26 h30 v18 a6 6 0 0 1 -6 6 h-18 a6 6 0 0 1 -6 -6 z" stroke="currentColor" stroke-width="1.8" fill="none"/><path d="M30 26 v-8 a4 4 0 0 1 4 -4" stroke="currentColor" stroke-width="1.8" fill="none"/><circle cx="30" cy="38" r="2" fill="currentColor"/></svg>`,
    cornerL: `<svg viewBox="0 0 60 80" fill="none"><path d="M6 6 v68 h48 v-46 h-22 v-22 z" stroke="currentColor" stroke-width="2.2" fill="none"/><path d="M34 6 v22 h20" stroke="currentColor" stroke-width="1.6"/></svg>`,
    counterFixed: `<svg viewBox="0 0 60 80" fill="none"><rect x="6" y="6" width="20" height="68" rx="2" stroke="currentColor" stroke-width="2.2"/><rect x="30" y="6" width="24" height="68" rx="2" stroke="currentColor" stroke-width="2.2" stroke-dasharray="3 3"/><path d="M10 20 h12" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`,
    tallOven: `<svg viewBox="0 0 60 80" fill="none"><rect x="8" y="4" width="44" height="72" rx="2" stroke="currentColor" stroke-width="2.2"/><rect x="14" y="10" width="32" height="22" rx="1.5" stroke="currentColor" stroke-width="1.8"/><rect x="14" y="36" width="32" height="14" rx="1.5" stroke="currentColor" stroke-width="1.8"/><rect x="14" y="54" width="32" height="18" rx="1.5" stroke="currentColor" stroke-width="1.8"/><path d="M20 44 h20 M20 63 h20" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`
  };

  const tsFront = (inner) => `<svg viewBox="0 0 60 80" fill="none"><rect x="14" y="3" width="32" height="74" rx="2" stroke="currentColor" stroke-width="2.2"/>${inner}</svg>`;
  libIcons.tsDoor = tsFront(`<circle cx="40" cy="42" r="1.8" fill="currentColor"/>`);
  libIcons.tsDrawerDoor = tsFront(`<path d="M14 62 h32" stroke="currentColor" stroke-width="2"/><path d="M26 69 h8" stroke="currentColor" stroke-width="2"/><circle cx="40" cy="34" r="1.8" fill="currentColor"/>`);
  libIcons.tsTwoDoors = tsFront(`<path d="M14 44 h32" stroke="currentColor" stroke-width="2"/><circle cx="40" cy="30" r="1.6" fill="currentColor"/><circle cx="40" cy="58" r="1.6" fill="currentColor"/>`);
  libIcons.tsDoorFlip = tsFront(`<path d="M14 20 h32" stroke="currentColor" stroke-width="2"/><path d="M26 14 h8" stroke="currentColor" stroke-width="2"/><circle cx="40" cy="50" r="1.8" fill="currentColor"/>`);

  const LIBRARY_GROUPS = [
    {
      id: 'doors',
      title_ar: 'الأبواب',
      title_en: 'Doors',
      icon: icons.door,
      items: [
        { id: 'door_right', label_ar: 'درفة يمين', label_en: 'Right Door', icon: libIcons.doorRight,
          matches: s => s.unitSubtype === 'standard' && s.doorType === 'single_right' },
        { id: 'door_left', label_ar: 'درفة شمال', label_en: 'Left Door', icon: libIcons.doorLeft,
          matches: s => s.unitSubtype === 'standard' && s.doorType === 'single_left' },
        { id: 'door_double', label_ar: 'درفتین', label_en: 'Double Doors', icon: libIcons.doorDouble,
          matches: s => s.unitSubtype === 'standard' && s.doorType === 'double' }
      ]
    },
    {
      id: 'drawers',
      title_ar: 'الأدراج',
      title_en: 'Drawers',
      icon: icons.drawers,
      items: [
        { id: 'drawer_mixed', label_ar: '1 صغير + 2 وسط', label_en: 'Mixed Drawers', icon: libIcons.drawerMixed,
          drawerCount: 3, pattern: 'small_first', smallH: 120,
          matches: s => s.unitSubtype === 'drawers' && s.drawerCount === 3 && s.drawerHeights[0] > 0 && s.drawerHeights[0] <= 150 },
        { id: 'drawer_2', label_ar: 'درجان متساويين', label_en: '2 Equal Drawers', icon: libIcons.drawer2,
          drawerCount: 2, pattern: 'target', targetH: 360,
          matches: s => s.unitSubtype === 'drawers' && s.drawerCount === 2 },
        { id: 'drawer_3', label_ar: '3 أدراج متساوية', label_en: '3 Equal Drawers', icon: libIcons.drawer3,
          drawerCount: 3, pattern: 'target', targetH: 360,
          matches: s => s.unitSubtype === 'drawers' && s.drawerCount === 3 && (s.drawerHeights[0] === 0 || s.drawerHeights[0] > 150) }
      ]
    },
    {
      id: 'special',
      title_ar: 'وحدات خاصة',
      title_en: 'Special Units',
      icon: icons.layers,
      items: [
        { id: 'oven_unit', label_ar: 'وحدة فرن', label_en: 'Oven Unit', icon: libIcons.oven,
          matches: s => s.unitSubtype === 'oven' },
        { id: 'sink_unit', label_ar: 'وحدة حوض', label_en: 'Sink Unit', icon: libIcons.sink,
          matches: s => s.unitSubtype === 'sink' },
        { id: 'corner_L', label_ar: 'كورنر L', label_en: 'L-Corner', icon: libIcons.cornerL,
          matches: s => s.unitSubtype === 'corner_L' },
        { id: 'counter_fixed', label_ar: 'سدة كونتر', label_en: 'Counter Fixed', icon: libIcons.counterFixed,
          matches: s => s.unitSubtype === 'counter_fixed' },
        { id: 'tall_oven', label_ar: 'دولاب فرن', label_en: 'Tall Oven', icon: libIcons.tallOven,
          matches: s => s.unitSubtype === 'tall_oven' }
      ]
    },
    {
      id: 'storage',
      title_ar: 'دواليب التخزين',
      title_en: 'Tall Storage',
      icon: icons.layers,
      items: [
        { id: 'ts_door', label_ar: 'درفة طويلة', label_en: 'Full-height Door', icon: libIcons.tsDoor,
          tsLayout: 'door', tsDrawerN: 0,
          matches: s => s.unitSubtype === 'tall_storage' && s.tsLayout === 'door' && !(s.tsDrawerN > 0) },
        { id: 'ts_drawer_door', label_ar: 'درج سفلي + درفة', label_en: 'Drawer + Door', icon: libIcons.tsDrawerDoor,
          tsLayout: 'door', tsDrawerN: 1,
          matches: s => s.unitSubtype === 'tall_storage' && s.tsLayout === 'door' && s.tsDrawerN > 0 },
        { id: 'ts_two_doors', label_ar: 'درفتين فوق بعض', label_en: 'Stacked Doors', icon: libIcons.tsTwoDoors,
          tsLayout: 'two_doors',
          matches: s => s.unitSubtype === 'tall_storage' && s.tsLayout === 'two_doors' },
        { id: 'ts_door_flip', label_ar: 'درفة سفلية + قلاب', label_en: 'Door + Flip-up', icon: libIcons.tsDoorFlip,
          tsLayout: 'door_flip',
          matches: s => s.unitSubtype === 'tall_storage' && s.tsLayout === 'door_flip' }
      ]
    }
  ];

  function detectActivePreset() {
    for (const group of LIBRARY_GROUPS) {
      for (const item of group.items) {
        if (item.matches && item.matches(state.settings)) return item.id;
      }
    }
    return null;
  }

  function enforceDoorType() {
    if (state.settings.width > DOUBLE_DOOR_THRESHOLD) {
      state.settings.doorType = 'double';
      return true;
    }
    return false;
  }

  function computeDrawerHeights(s, pattern, targetH, smallH) {
    const topGap = 30;
    const gap    = 30;
    const n      = s.drawerCount;
    if (n < 1) return [];

    const available = s.height - topGap - (n - 1) * gap;
    if (available <= 0) return new Array(n).fill(100);

    if (pattern === 'small_first') {
      const small = Math.min(smallH || 120, Math.max(80, Math.floor(available / (n + 1))));
      const rest  = Math.max(80, Math.floor((available - small) / (n - 1)));
      return [small, ...new Array(n - 1).fill(rest)];
    }

    if (targetH && targetH * n <= available) {
      return new Array(n).fill(targetH);
    }

    const each = Math.max(80, Math.floor(available / n));
    return new Array(n).fill(each);
  }

  function applyPreset(presetId) {
    for (const group of LIBRARY_GROUPS) {
      const item = group.items.find(i => i.id === presetId);
      if (!item) continue;

      const s = state.settings;
      const wasTall = s.unitSubtype === 'tall_oven' || s.unitSubtype === 'tall_storage';

      if (group.id === 'doors') {
        s.unitSubtype = 'standard';
        if (presetId === 'door_right')       s.doorType = 'single_right';
        else if (presetId === 'door_left')   s.doorType = 'single_left';
        else if (presetId === 'door_double') s.doorType = 'double';
      } else if (group.id === 'drawers') {
        s.unitSubtype = 'drawers';
        s.drawerCount = item.drawerCount || 3;
        s.drawerHeights = computeDrawerHeights(s, item.pattern, item.targetH, item.smallH);
      } else if (group.id === 'storage') {
        s.unitSubtype = 'tall_storage';
        s.tsLayout = item.tsLayout || 'door';
        if (item.tsDrawerN !== undefined) s.tsDrawerN = item.tsDrawerN;
        if (s.tsLayout === 'door_flip') s.tsSplitH = 1700;
        else if (s.tsLayout === 'two_doors') s.tsSplitH = 1200;
        if (s.height < 2000) s.height = 2200;   // 220 سم بدون الرجل
      } else if (group.id === 'special') {
        if (presetId === 'oven_unit') {
          s.unitSubtype = 'oven';
        } else if (presetId === 'sink_unit') {
          s.unitSubtype = 'sink';
        } else if (presetId === 'corner_L') {
          s.unitSubtype = 'corner_L';
        } else if (presetId === 'counter_fixed') {
          s.unitSubtype = 'counter_fixed';
          if (s.width !== 1100) {
            s.width = 1100;
            s.doorType = 'double';
          }
        } else if (presetId === 'tall_oven') {   // ⭐ جديد
          s.unitSubtype = 'tall_oven';
          if (!s.tallBottomType) s.tallBottomType = 'drawers';
          if (s.height < 2000) s.height = 2200;   // 220 سم بدون الرجل
        }
      }

      // ⭐ الارتفاع الافتراضي 78 لكل الوحدات ما عدا دولاب الفرن (220)
      if (s.unitSubtype !== 'tall_oven' && s.unitSubtype !== 'tall_storage' && wasTall && s.height >= 1500) s.height = 780;
      // ⭐ العرض الافتراضي 60 ما عدا السدة (110)
      if (s.unitSubtype !== 'counter_fixed' && s.width === 1100) s.width = 600;

      if (s.width > DOUBLE_DOOR_THRESHOLD && s.unitSubtype === 'standard') {
        s.doorType = 'double';
      }
      render();
      return;
    }
  }

  // ===== تصنيفات المكتبة: نقل أي وحدة لتصنيف تاني (بيتحفظ في الإعدادات) =====
  const isEn = () => state.lang === 'en';
  const groupTitle = (g) => isEn() ? (g.title_en || g.title_ar) : g.title_ar;
  const itemLabel  = (it) => isEn() ? (it.label_en || it.label_ar) : it.label_ar;
  const itemLabel2 = (it) => isEn() ? it.label_ar : it.label_en;

  function libMoves() {
    if (!state.settings.libMoves || typeof state.settings.libMoves !== 'object') state.settings.libMoves = {};
    return state.settings.libMoves;
  }
  function originalGroupOf(itemId) {
    const g = LIBRARY_GROUPS.find(gr => gr.items.some(i => i.id === itemId));
    return g ? g.id : null;
  }
  function effectiveGroupId(itemId, origId) {
    const m = libMoves()[itemId];
    return (m && LIBRARY_GROUPS.some(g => g.id === m)) ? m : origId;
  }
  function getEffectiveGroups() {
    const out = LIBRARY_GROUPS.map(g => ({ ...g, items: [] }));
    LIBRARY_GROUPS.forEach(g => g.items.forEach(item => {
      const gid = effectiveGroupId(item.id, g.id);
      (out.find(x => x.id === gid) || out.find(x => x.id === g.id)).items.push(item);
    }));
    return out;
  }
  function moveItemToGroup(itemId, groupId) {
    const orig = originalGroupOf(itemId);
    if (!orig) return;
    if (groupId === orig) delete libMoves()[itemId]; else libMoves()[itemId] = groupId;
    bridge.call('save_settings', JSON.stringify(state.settings));
    render();
    showToast(isEn() ? '✅ Moved' : '✅ تم نقل الوحدة');
  }

  function getGroupCount(groupId) {
    const g = getEffectiveGroups().find(x => x.id === groupId);
    return g ? g.items.length : 0;
  }

  function getAllItemsCount() {
    return LIBRARY_GROUPS.reduce((sum, g) => sum + g.items.length, 0);
  }

  function matchSearch(item, q) {
    if (!q) return true;
    return item.label_ar.toLowerCase().includes(q) ||
           item.label_en.toLowerCase().includes(q);
  }

  // ---- التنقل من القائمة الجانبية: مكتبة / حائط / ركن / وحدات خاصة ----
  const NAV_CORNER_IDS = ['corner_L'];
  function navGroups(all) {
    if (state.nav === 'corner') {
      const items = all.flatMap(g => g.items).filter(i => NAV_CORNER_IDS.includes(i.id));
      return [{ id: 'corner', title_ar: 'خزائن الركن', title_en: 'Corner Cabinets', icon: icons.layers, items }];
    }
    if (state.nav === 'special') {
      return all
        .filter(g => g.id === 'special' || g.id === 'storage')
        .map(g => ({ ...g, items: g.items.filter(i => !NAV_CORNER_IDS.includes(i.id)) }));
    }
    return all;
  }
  const navIsLibrary = () => state.nav === 'library' || !state.nav;

  function getFilteredGroups() {
    const q = state.libSearch.trim().toLowerCase();
    const all = navGroups(getEffectiveGroups());
    const groupsToShow = (!navIsLibrary() || state.libFilter === 'all') ? all : all.filter(g => g.id === state.libFilter);

    return groupsToShow
      .map(group => ({ ...group, items: group.items.filter(item => matchSearch(item, q)) }))
      // تصنيف فاضي بيفضل ظاهر لو هو الفلتر المختار (عشان تسحب عليه وحدات)
      .filter(g => g.items.length > 0 || (navIsLibrary() && state.libFilter === g.id && !q));
  }

  function getFilteredCount() {
    return getFilteredGroups().reduce((sum, g) => sum + g.items.length, 0);
  }

  function renderLibraryToolbar() {
    const ph = isEn() ? 'Search units… (Arabic or English)' : 'ابحث عن وحدة... (بالعربي أو الإنجليزي)';
    return `
      <section class="panel-card lib-toolbar-card">
        <div class="lib-search">
          <div class="lib-search-icon">${icons.search}</div>
          <input type="text" id="libSearchInput"
                 placeholder="${ph}"
                 value="${state.libSearch.replace(/"/g, '&quot;')}"
                 autocomplete="off" spellcheck="false"/>
          <button type="button" class="lib-search-clear" id="libSearchClear"
                  style="display: ${state.libSearch ? 'inline-flex' : 'none'};"
                  aria-label="clear">✕</button>
        </div>
        ${navIsLibrary() ? `<div class="lib-chips">
          ${renderFilterChip('all', isEn() ? 'All' : 'الكل', getAllItemsCount())}
          ${getEffectiveGroups().map(g => renderFilterChip(g.id, groupTitle(g), g.items.length)).join('')}
        </div>` : ''}
        <div class="lib-results">
          <span id="libResults">${resultsText(getFilteredCount())}</span>
          <span class="lib-hint">${isEn() ? 'Tip: drag a card onto a category, or use ⇄ to move it' : 'نصيحة: اسحب الكارت على تصنيف تاني أو اضغط ⇄ لنقله'}</span>
        </div>
      </section>
    `;
  }

  function resultsText(n) { return isEn() ? `${n} result${n === 1 ? '' : 's'}` : `${n} نتيجة`; }

  function renderFilterChip(id, label, count) {
    const active = state.libFilter === id ? 'active' : '';
    return `
      <button type="button" class="lib-chip ${active}" data-filter="${id}">
        <span>${label}</span>
        <b>${count}</b>
      </button>
    `;
  }

  function renderLibraryGrid() {
    const activeId = detectActivePreset();
    const groups = getFilteredGroups();

    if (groups.length === 0) {
      return `
        <section class="panel-card lib-empty-card">
          <div class="lib-empty">
            <div class="lib-empty-icon">🔍</div>
            <p>${isEn() ? 'No results for' : 'مفيش نتائج لـ'} "<b>${state.libSearch}</b>"</p>
            <button type="button" class="btn btn-secondary" id="libResetBtn">مسح البحث</button>
          </div>
        </section>
      `;
    }

    return groups.map(group => renderLibraryGroup(group, activeId)).join('');
  }

  function navHeadText() {
    const en = isEn();
    switch (state.nav) {
      case 'wall':    return [en ? 'Wall Cabinets' : 'خزائن الحائط', en ? 'Upper units & cladding' : 'الوحدات العلوية والتجاليد'];
      case 'corner':  return [en ? 'Corner Cabinets' : 'خزائن الركن', en ? 'L-shaped corner units' : 'وحدات الركن L'];
      case 'special': return [en ? 'Special Units' : 'الوحدات الخاصة', en ? 'Oven, sink, counter & tall units' : 'فرن وحوض وسدة ودواليب طويلة'];
      default:        return [i18n.t('cabinets.title'), i18n.t('cabinets.desc')];
    }
  }

  function renderWallPlaceholder() {
    const en = isEn();
    return `
      <section class="panel-card lib-empty-card wall-soon">
        <div class="lib-empty">
          <div class="lib-empty-icon">🧱</div>
          <h3>${en ? 'Wall units & cladding' : 'الوحدات العلوية والتجاليد'}</h3>
          <p>${en ? 'This section is ready for the next stage: upper cabinets and cladding panels will be added here.'
                  : 'القسم ده جاهز للمرحلة الجاية: هنضيف هنا الوحدات العلوية (خزائن الحائط) والتجاليد.'}</p>
          <button type="button" class="btn btn-secondary" id="wallBackBtn">${en ? 'Back to library' : 'الرجوع للمكتبة'}</button>
        </div>
      </section>`;
  }

  function renderCabinetsTab() {
    const [navTitle, navDesc] = navHeadText();
    return `
      <section class="panel-card">
        <div class="card-head">
          <div class="card-icon">${icons.cube}</div>
          <div class="title-block">
            <h2>${navTitle}</h2>
            <p>${navDesc}</p>
          </div>
        </div>
      </section>

      ${state.nav === 'wall' ? renderWallPlaceholder() : `
      ${renderLibraryToolbar()}

      <div id="libGridContainer">
        ${renderLibraryGrid()}
      </div>`}

      <div class="actions-row">
        <button class="btn btn-primary" id="createBtn">
          ${icons.cube}
          <span class="t">
            <span>${i18n.t('action.create')}</span>
            <em>${i18n.t('action.create.sub')}</em>
          </span>
        </button>
        <button class="btn btn-secondary" id="saveBtn">
          ${icons.gear}
          <span class="t">
            <span>${i18n.t('action.save')}</span>
            <em>${i18n.t('action.save.sub')}</em>
          </span>
        </button>
      </div>
    `;
  }

  function renderLibraryGroup(group, activeId) {
    const count = group.items.length;
    const sub = isEn() ? group.title_ar : (group.title_en || '');
    const body = count
      ? group.items.map(item => renderLibraryCard(item, activeId)).join('')
      : `<div class="lib-group-empty">${isEn() ? 'Empty — drag a unit here or use ⇄ on any card' : 'تصنيف فاضي — اسحب وحدة هنا أو استخدم ⇄ على أي كارت'}</div>`;
    return `
      <section class="panel-card lib-group" data-group="${group.id}">
        <div class="card-head">
          <div class="card-icon">${group.icon}</div>
          <div class="title-block">
            <h2>${groupTitle(group)} <span class="lib-count">${count}</span></h2>
            <p>${sub}</p>
          </div>
        </div>
        <div class="lib-grid">${body}</div>
      </section>
    `;
  }

  function renderLibraryCard(item, activeId) {
    const active = activeId === item.id ? 'active' : '';
    const imgPath = `images/units/${item.id}.png`;
    return `
      <button class="lib-card ${active}" data-preset="${item.id}" draggable="true">
        <span class="lib-move" role="button" tabindex="0" data-move="${item.id}"
              title="${isEn() ? 'Move to another category' : 'نقل لتصنيف تاني'}">⇄</span>
        <div class="lib-icon">
          <img class="lib-img" src="${imgPath}" alt="${item.label_en}"
               onerror="this.style.display='none'; this.parentElement.classList.add('use-svg');" />
          <div class="lib-svg">${item.icon}</div>
        </div>
        <b>${itemLabel(item)}</b>
        <em>${itemLabel2(item)}</em>
      </button>
    `;
  }

  function renderDimensionsCard(isCornerL) {
    if (isCornerL) return '';
    const s = state.settings;
    return `
      <div class="config-card">
        <h3>${icons.edit} الأبعاد</h3>
        <p class="dim-desc">الأبعاد الافتراضية (بالسنتيمتر)</p>
        <div class="dim-stack">
          ${dimField('width',  'العرض',     s.width)}
          ${dimField('height', 'الارتفاع',  s.height)}
          ${dimField('depth',  'العمق',     s.depth)}
        </div>
        <div class="lock-banner">
          <div class="lock-ico">${icons.lock}</div>
          <div><strong>سماكة الجانب (مقفل)</strong><span>1.8 سم</span></div>
          <span class="value-pill">1.8 cm</span>
        </div>
      </div>`;
  }

  function renderRightPanel() {
    const s = state.settings;
    const isDrawers = s.unitSubtype === 'drawers';
    const isOven = s.unitSubtype === 'oven';
    const isStandard = s.unitSubtype === 'standard';
    const isSink = s.unitSubtype === 'sink';
    const isCornerL = s.unitSubtype === 'corner_L';
    const isCounterFixed = s.unitSubtype === 'counter_fixed';
    const isTallOven = s.unitSubtype === 'tall_oven';   // ⭐ جديد
    const isTallStorage = s.unitSubtype === 'tall_storage';

    return `
      ${renderDimensionsCard(isCornerL)}

      ${isStandard ? renderDoorOptionsPanel() : ''}
      ${isSink ? renderSinkDoorPanel() : ''}
      ${isDrawers ? renderDrawerOptionsPanel() : ''}
      ${isOven ? renderOvenOptionsPanel() : ''}
      ${isCornerL ? renderCornerLDimensionsPanel() : ''}
      ${isCounterFixed ? renderCounterFixedPanel() : ''}
      ${isTallOven ? renderTallOvenPanel() : ''}
      ${isTallStorage ? renderTallStoragePanel() : ''}

      <div class="config-card">
        <h3>التكوين الحالي</h3>
        <div class="config-list">
          ${renderCurrentConfig(s)}
        </div>
      </div>
    `;
  }

  function renderDoorOptionsPanel() {
    const s = state.settings;
    const isWide = s.width > DOUBLE_DOOR_THRESHOLD;
    return `
      <div class="config-card">
        <h3>${icons.door} تكوينات الأبواب</h3>
        <p class="dim-desc">اختر نوع الأبواب لخزانتك</p>
        <div class="door-grid door-grid-3col" id="doorGrid">
          ${doorOption('single_left', 'باب يسار', 'Single Left', 'left', isWide)}
          ${doorOption('single_right', 'باب يمين', 'Single Right', 'right', isWide)}
          ${doorOption('double', 'بابان', 'Double', 'double', false)}
        </div>
        <div class="inline-field" style="margin-top:10px;">
          <div class="ico">${icons.shelves}</div>
          <label><b>عدد الأرفف</b><span>اختر عدد الأرفف</span></label>
          <div class="ctrl">
            <input type="number" id="shelvesInput" min="0" max="8" value="${s.shelves}"/>
            <div class="steppers">
              <button type="button" data-step="1">▲</button>
              <button type="button" data-step="-1">▼</button>
            </div>
          </div>
        </div>
      </div>
    `;
  }

  function renderSinkDoorPanel() {
    const s = state.settings;
    const isWide = s.width > DOUBLE_DOOR_THRESHOLD;
    return `
      <div class="config-card">
        <h3>${icons.door} تكوينات أبواب الحوض</h3>
        <p class="dim-desc">بورديوم 17مم بدون ضهرية/رف</p>
        <div class="door-grid door-grid-3col" id="doorGrid">
          ${doorOption('single_left', 'باب يسار', 'Single Left', 'left', isWide)}
          ${doorOption('single_right', 'باب يمين', 'Single Right', 'right', isWide)}
          ${doorOption('double', 'بابان', 'Double', 'double', false)}
        </div>
      </div>
    `;
  }

  function renderDrawerOptionsPanel() {
    const s = state.settings;
    return `
      <div class="config-card">
        <h3>${icons.drawers} تكوين الأدراج</h3>
        <p class="dim-desc">اختر عدد الأدراج وارتفاع كل درج (0 = توزيع تلقائي)</p>
        <div class="inline-field">
          <div class="ico">${icons.plus}</div>
          <label><b>عدد الأدراج</b><span>من 1 إلى 6 أدراج</span></label>
          <div class="ctrl">
            <input type="number" id="drawerCountInput" min="1" max="6" value="${s.drawerCount}"/>
            <div class="steppers">
              <button type="button" data-drawer-step="1">▲</button>
              <button type="button" data-drawer-step="-1">▼</button>
            </div>
          </div>
        </div>
        <div style="margin-top:12px;">${renderDrawerHeights(s)}</div>
        <p style="font-size:11px;color:var(--text-3);margin-top:10px;line-height:1.6;">
          💡 المقابض: <b>L</b> للدرج العلوي، <b>C</b> لباقي الأدراج.<br>
          💡 <b>0</b> = توزيع تلقائي حسب ارتفاع الوحدة.
        </p>
      </div>
    `;
  }

  function renderOvenOptionsPanel() {
    const s = state.settings;
    const showBox = s.ovenDrawer !== 'none';
    return `
      <div class="config-card">
        <h3>${icons.gear} موضع الدرج في وحدة الفرن</h3>
        <p class="dim-desc">اختر أين يوضع الدرج بالنسبة للفرن</p>
        <div class="door-grid door-grid-3col" id="ovenDrawerGrid">
          ${ovenDrawerOption('none',  'بدون',  'None',  'cube')}
          ${ovenDrawerOption('above', 'فوق',   'Above', 'drawers')}
          ${ovenDrawerOption('below', 'تحت',   'Below', 'drawers')}
        </div>
        ${showBox ? `
          <div style="margin-top:14px;">
            <h3 style="margin-bottom:8px;">${icons.cube} بوكس الدرج</h3>
            <div class="door-grid door-grid-2col" id="ovenBoxGrid">
              ${ovenBoxOption('with',    'ببوكس داخلي', 'With Box', 'drawers')}
              ${ovenBoxOption('without', 'هواية',       'No Box',   'cube')}
            </div>
          </div>
        ` : ''}
      </div>
    `;
  }

  // ⭐⭐⭐ جديد: بانل دولاب الفرن
  function renderTallOvenPanel() {
    const s = state.settings;
    return `
      <div class="config-card">
        <h3>${icons.cube} ${i18n.t('tallOven.title')}</h3>
        <p class="dim-desc">${i18n.t('tallOven.desc')}</p>
        <h4 style="font-size:11.5px;color:var(--accent);margin:10px 0 6px;">
          ${i18n.t('tallOven.bottom')}
        </h4>
        <div class="door-grid door-grid-2col" id="tallBottomGrid">
          ${tallBottomOption('drawer1', 'درج واحد', '1 Drawer', 'drawers')}
          ${tallBottomOption('drawers', i18n.t('tallOven.drawers'), '2 Drawers', 'drawers')}
          ${tallBottomOption('door',    i18n.t('tallOven.door'),    'Single Door', 'door')}
          ${tallBottomOption('double',  i18n.t('tallOven.double'),  'Double Doors', 'door')}
        </div>

        <h4 style="font-size:11.5px;color:var(--accent);margin:14px 0 6px;">
          ارتفاعات الأقسام
        </h4>
        <div class="dim-stack">
          ${dimField('tallBottomH', 'القسم السفلي (أدراج / درف)', s.tallBottomH || 620)}
          ${dimField('tallOvenH',   'فتحة الفرن',                 s.tallOvenH   || 600)}
          ${dimField('tallMicroH',  'درفة الميكروويف',            s.tallMicroH  || 450)}
        </div>
        <p class="dim-desc" style="margin-top:8px;${tallTopMm(s) < 100 ? 'color:#ff6b6b;' : ''}">
          الدرفة العلوية (تلقائي): ${mmToCm(tallTopMm(s))} سم
          ${tallTopMm(s) < 100 ? ' — الارتفاعات كبيرة، هتتقلّل درفة الميكروويف' : ''}
        </p>
      </div>
    `;
  }

  // الدرفة العلوية = الباقي بعد (السفلي + الهواية 130 مم + الفرن + درفة الميكروويف + فراغ 3 مم)
  function tallTopMm(s) {
    return s.height - (s.tallBottomH || 620) - 130 - (s.tallOvenH || 600) - (s.tallMicroH || 450) - 3;
  }

  // ⭐⭐⭐ جديد: خيار القسم السفلي
  function tallBottomOption(id, labelAr, labelEn, iconKey) {
    const active = state.settings.tallBottomType === id ? 'active' : '';
    return `
      <button class="door-opt ${active}" data-tall-bottom="${id}">
        <span class="dot"></span>
        <div class="ico">${icons[iconKey] || icons.cube}</div>
        <b>${labelAr}</b>
        <em>${labelEn}</em>
      </button>`;
  }


  // ⭐⭐⭐ دولاب التخزين: بانل التكوين
  function tsOpt(attr, id, active, labelAr, labelEn, iconKey) {
    return `
      <button class="door-opt ${active ? 'active' : ''}" ${attr}="${id}">
        <span class="dot"></span>
        <div class="ico">${icons[iconKey] || icons.cube}</div>
        <b>${labelAr}</b>
        <em>${labelEn}</em>
      </button>`;
  }

  function tsField(key, label, valueMm, maxCm, hint) {
    const cm = mmToCm(valueMm || 0);
    return `
      <div class="dim-field" style="margin-bottom:8px;">
        <div class="dim-field-label"><span>${label}</span><span class="ar">cm</span></div>
        <div class="ctrl ctrl-lg">
          <input type="number" data-ts-field="${key}" min="0" max="${maxCm}" value="${cm}"/>
          <span class="unit">سم</span>
          <div class="steppers">
            <button type="button" data-ts-step="${key}" data-dir="1" data-max="${maxCm}">▲</button>
            <button type="button" data-ts-step="${key}" data-dir="-1" data-max="${maxCm}">▼</button>
          </div>
        </div>
        ${hint ? `<p class="dim-desc" style="margin-top:4px;">${hint}</p>` : ''}
      </div>`;
  }

  function renderTallStoragePanel() {
    const s = state.settings;
    const isWide = s.width > DOUBLE_DOOR_THRESHOLD;
    const L = s.tsLayout;
    const hasHingedDoors = true;
    const maxClear = Math.max(20, mmToCm(s.height + 100));
    return `
      <div class="config-card">
        <h3>${icons.cube} دولاب التخزين</h3>
        <p class="dim-desc">وش بدون فتحات — اختر شكل الأوجه</p>
        <div class="door-grid door-grid-2col" id="tsLayoutGrid">
          ${tsOpt('data-ts-layout', 'door',        L === 'door',        'درفة / درفتين',    'Door(s)',   'door')}
          ${tsOpt('data-ts-layout', 'two_doors',   L === 'two_doors',   'درفتين فوق بعض',   'Stacked Doors', 'door')}
          ${tsOpt('data-ts-layout', 'door_flip',   L === 'door_flip',   'درفة سفلية + قلاب', 'Door + Flip-up', 'door')}
        </div>

        <div class="inline-field" style="margin-top:10px;">
          <div class="ico">${icons.drawers}</div>
          <label><b>عدد الأدراج السفلية</b><span>0 = بدون أدراج (حتى 4)</span></label>
          <div class="ctrl">
            <input type="number" id="tsDrawerNInput" min="0" max="4" value="${s.tsDrawerN || 0}"/>
            <div class="steppers">
              <button type="button" data-ts-drawern-step="1">▲</button>
              <button type="button" data-ts-drawern-step="-1">▼</button>
            </div>
          </div>
        </div>
        ${s.tsDrawerN > 0 ? `<div style="margin-top:8px;">${tsField('tsDrawerH', 'ارتفاع كل درج', s.tsDrawerH, 60)}</div>` : ''}
        ${(L === 'two_doors' || L === 'door_flip') ? `<div style="margin-top:10px;">
            ${tsField('tsSplitH', L === 'door_flip' ? 'ارتفاع الدرفة السفلية (من الأرض)' : 'ارتفاع الفاصل بين الدرفتين (من الأرض)', s.tsSplitH, maxClear)}
          </div>` : ''}

        <h4 style="font-size:11.5px;color:var(--accent);margin:12px 0 6px;">المقابض</h4>
        <div class="door-grid door-grid-2col" id="tsHandlesGrid">
          ${tsOpt('data-ts-handles', 'no',  !s.tsHandles, 'بدون مقابض (لمس)', 'Push-to-open', 'cube')}
          ${tsOpt('data-ts-handles', 'yes',  s.tsHandles, 'مقابض C و L', 'C between / L on top',  'cube')}
        </div>

        <h4 style="font-size:11.5px;color:var(--accent);margin:12px 0 6px;">اتجاه الفتح</h4>
        <div class="door-grid door-grid-3col" id="doorGrid">
          ${doorOption('single_left', 'باب يسار', 'Single Left', 'left', isWide)}
          ${doorOption('single_right', 'باب يمين', 'Single Right', 'right', isWide)}
          ${doorOption('double', 'بابان', 'Double', 'double', false)}
        </div>
        <p class="dim-desc" style="margin-top:6px;">الاتجاه بيطبّق على الدرف المفصلية (القلاب بيفتح لفوق)</p>
      </div>

      <div class="config-card">
        <h3>${icons.shelves} الرفوف الداخلية</h3>
        <p class="dim-desc">كل المقاسات من الأرض (بما فيها الرجل)</p>
        <div class="inline-field">
          <div class="ico">${icons.shelves}</div>
          <label><b>عدد الرفوف</b><span>من 0 إلى 12</span></label>
          <div class="ctrl">
            <input type="number" id="tsShelvesInput" min="0" max="12" value="${s.tsShelves}"/>
            <div class="steppers">
              <button type="button" data-ts-shelves-step="1">▲</button>
              <button type="button" data-ts-shelves-step="-1">▼</button>
            </div>
          </div>
        </div>
        <div style="margin-top:10px;">
          ${tsField('tsClearH', 'فراغ سفلي بدون رفوف (للمقاشات والنضافة)', s.tsClearH, maxClear,
              '0 = توزيع عادي — أول رف بيبدأ عند نهاية الفراغ')}
          <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:8px;">
            <button type="button" class="lib-chip" data-ts-clear="0">بدون فراغ</button>
            <button type="button" class="lib-chip" data-ts-clear="1000">100 سم</button>
            <button type="button" class="lib-chip" data-ts-clear="1500">150 سم</button>
          </div>
        </div>
        <div class="dim-field" style="margin-bottom:4px;">
          <div class="dim-field-label"><span>مواضع الرفوف يدوي (اختياري)</span><span class="ar">cm</span></div>
          <div class="ctrl ctrl-lg">
            <input type="text" id="tsShelfPosInput" placeholder="مثال: 150, 180, 200" value="${s.tsShelfPos || ''}" style="width:100%;"/>
          </div>
          <p class="dim-desc" style="margin-top:4px;">لو كتبت مواضع، بتتجاهل العدد والفراغ السفلي</p>
        </div>
      </div>
    `;
  }

  function tsPayload(s) {
    const pos = String(s.tsShelfPos || '').split(/[,،\s]+/)
      .map(x => parseFloat(x)).filter(x => !isNaN(x) && x > 0).map(x => Math.round(x * 10));
    return {
      layout: s.tsLayout || 'door',
      handles: !!s.tsHandles,
      drawer_n: s.tsDrawerN || 0,
      drawer_h: s.tsDrawerH || 250,
      split_h: s.tsSplitH || 1200,
      shelves: s.tsShelves,
      clear_h: s.tsClearH || 0,
      shelf_pos: pos
    };
  }

  function renderCornerLDimensionsPanel() {
    const s = state.settings;
    const heightField = dimFieldCornerL('height', 'الارتفاع', s.height);
    return `
      <div class="config-card">
        <h3>${icons.cube} أبعاد كورنر L</h3>
        <p class="dim-desc">عرض وعمق كل ضلع</p>

        <div style="margin-bottom:12px;padding-bottom:10px;border-bottom:1px dashed var(--border);">
          ${heightField}
        </div>

        <h4 style="font-size:11.5px;color:var(--accent);margin:10px 0 6px;">الضلع اليمين</h4>
        ${dimFieldCornerL('cornerWRight', 'عرض اليمين', s.cornerWRight)}
        ${dimFieldCornerL('cornerDRight', 'عمق اليمين', s.cornerDRight)}

        <h4 style="font-size:11.5px;color:var(--accent);margin:14px 0 6px;">الضلع الشمال</h4>
        ${dimFieldCornerL('cornerWLeft', 'عرض الشمال', s.cornerWLeft)}
        ${dimFieldCornerL('cornerDLeft', 'عمق الشمال', s.cornerDLeft)}
      </div>
    `;
  }

  function renderCounterFixedPanel() {
    const s = state.settings;
    return `
      <div class="config-card">
        <h3>${icons.cube} إعدادات سدة الكونتر</h3>
        <p class="dim-desc">الجزء الثابت من الوش + بقية الوحدة باب</p>
        <div class="dim-field" style="margin-bottom:10px;">
          <div class="dim-field-label"><span>جهة الجزء الثابت</span></div>
          <div class="door-grid door-grid-2col" id="cfSideGrid">
            <button class="door-opt ${s.fixedSide === 'left' ? 'active' : ''}" data-cf-side="left">
              <span class="dot"></span><b>يسار</b><em>Left</em>
            </button>
            <button class="door-opt ${s.fixedSide === 'right' ? 'active' : ''}" data-cf-side="right">
              <span class="dot"></span><b>يمين</b><em>Right</em>
            </button>
          </div>
        </div>
        ${dimFieldCounterFixed('counterWidth', 'عرض السدة', s.counterWidth)}
        ${dimFieldCounterFixed('fillerWidth',  'عرض القطعة الثابتة', s.fillerWidth)}
      </div>`;
  }

  function dimFieldCounterFixed(key, label, valueMm) {
    const cmValue = mmToCm(valueMm);
    return `
      <div class="dim-field" style="margin-bottom:8px;">
        <div class="dim-field-label"><span>${label}</span><span class="ar">cm</span></div>
        <div class="ctrl ctrl-lg">
          <input type="number" data-field="${key}" min="5" max="200" value="${cmValue}"/>
          <span class="unit">سم</span>
          <div class="steppers">
            <button type="button" data-step-field="${key}" data-dir="1">▲</button>
            <button type="button" data-step-field="${key}" data-dir="-1">▼</button>
          </div>
        </div>
      </div>`;
  }

  function dimFieldCornerL(key, label, valueMm) {
    const cmValue = mmToCm(valueMm);
    return `
      <div class="dim-field" style="margin-bottom:8px;">
        <div class="dim-field-label"><span>${label}</span><span class="ar">cm</span></div>
        <div class="ctrl ctrl-lg">
          <input type="number" data-field="${key}" min="20" max="300" value="${cmValue}"/>
          <span class="unit">سم</span>
          <div class="steppers">
            <button type="button" data-step-field="${key}" data-dir="1">▲</button>
            <button type="button" data-step-field="${key}" data-dir="-1">▼</button>
          </div>
        </div>
      </div>`;
  }

  function renderCurrentConfig(s) {
    const doorLabel = { single_left: 'باب يسار', single_right: 'باب يمين', double: 'بابان' }[s.doorType];
    const subtypeLabel = {
      standard: 'عادية', drawers: 'أدراج', oven: 'فرن',
      corner_L: 'كورنر L', sink: 'حوض', counter_fixed: 'سدة كونتر',
      tall_oven: 'دولاب فرن',   // ⭐ جديد
      tall_storage: 'دولاب تخزين'
    }[s.unitSubtype] || 'عادية';

    const isDrawers = s.unitSubtype === 'drawers';
    const isOven = s.unitSubtype === 'oven';
    const isStandard = s.unitSubtype === 'standard';
    const isSink = s.unitSubtype === 'sink';
    const isCornerL = s.unitSubtype === 'corner_L';
    const isCounterFixed = s.unitSubtype === 'counter_fixed';
    const isTallOven = s.unitSubtype === 'tall_oven';   // ⭐ جديد
    const isTallStorage = s.unitSubtype === 'tall_storage';
    const tsLayoutLabel = ({ door: 'درفة / درفتين', two_doors: 'درفتين فوق بعض', door_flip: 'درفة سفلية + قلاب' }[s.tsLayout] || '') + (s.tsDrawerN > 0 ? ` + ${s.tsDrawerN} أدراج` : '');
    const showOvenBoxRow = isOven && s.ovenDrawer !== 'none';

    // ⭐ ترجمة نوع القسم السفلي
    const tallBottomLabel = { drawer1: 'درج واحد', drawers: 'درجين', door: 'درفة', double: 'درفتين' }[s.tallBottomType] || 'درجين';

    return `
      ${configRow(icons.cube, 'نوع الوحدة', subtypeLabel)}
      ${isTallOven ? configRow(icons.drawers, 'القسم السفلي', tallBottomLabel) : ''}
      ${isTallStorage ? configRow(icons.door, 'شكل الأوجه', tsLayoutLabel) : ''}
      ${isTallStorage ? configRow(icons.door, 'المقابض', s.tsHandles ? 'C و L' : 'بدون (لمس)') : ''}
      ${isTallStorage ? configRow(icons.door, 'اتجاه الفتح', doorLabel) : ''}
      ${isTallStorage ? configRow(icons.shelves, 'الرفوف', (s.tsShelfPos && s.tsShelfPos.trim()) ? 'مواضع يدوية' : s.tsShelves) : ''}
      ${isTallStorage && s.tsClearH > 0 ? configRow(icons.dimH, 'فراغ سفلي', `${mmToCm(s.tsClearH)} سم`) : ''}
      ${isDrawers ? configRow(icons.drawers, 'عدد الأدراج', s.drawerCount) : ''}
      ${isCornerL ? configRow(icons.dimW, 'عرض اليمين', `${mmToCm(s.cornerWRight)} سم`) : ''}
      ${isCornerL ? configRow(icons.dimD, 'عمق اليمين', `${mmToCm(s.cornerDRight)} سم`) : ''}
      ${isCornerL ? configRow(icons.dimW, 'عرض الشمال', `${mmToCm(s.cornerWLeft)} سم`) : ''}
      ${isCornerL ? configRow(icons.dimD, 'عمق الشمال', `${mmToCm(s.cornerDLeft)} سم`) : ''}
      ${isCounterFixed ? configRow(icons.cube, 'جهة ثابتة',
          { left: 'يسار', right: 'يمين' }[s.fixedSide] || 'يسار') : ''}
      ${isCounterFixed ? configRow(icons.dimW, 'عرض السدة', `${mmToCm(s.counterWidth)} سم`) : ''}
      ${isCounterFixed ? configRow(icons.dimW, 'القطعة الثابتة', `${mmToCm(s.fillerWidth)} سم`) : ''}
      ${!isCornerL ? configRow(icons.dimW, 'العرض',  `${mmToCm(s.width)} سم`) : ''}
      ${configRow(icons.dimH, 'الارتفاع', `${mmToCm(s.height)} سم`)}
      ${!isCornerL ? configRow(icons.dimD, 'العمق',  `${mmToCm(s.depth)} سم`) : ''}
      ${isStandard ? configRow(icons.door, 'نوع الباب', doorLabel) : ''}
      ${isSink ? configRow(icons.door, 'نوع الباب', doorLabel) : ''}
      ${isStandard ? configRow(icons.shelves, 'الأرفف', s.shelves) : ''}
      ${isOven ? configRow(icons.drawers, 'موضع الدرج',
          { none: 'بدون', above: 'فوق الفرن', below: 'تحت الفرن' }[s.ovenDrawer] || 'بدون') : ''}
      ${showOvenBoxRow ? configRow(icons.cube, 'نوع الدرج', s.ovenDrawerBox ? 'ببوكس' : 'هواية') : ''}
    `;
  }

  function renderDrawerHeights(s) {
    const count = s.drawerCount || 3;
    let html = '';
    for (let i = 0; i < count; i++) {
      const hMm = s.drawerHeights[i] || 0;
      const cm  = mmToCm(hMm);
      html += `
        <div class="dim-field" style="margin-bottom:8px;">
          <div class="dim-field-label"><span>ارتفاع الدرج ${i + 1}</span><span class="ar">cm</span></div>
          <div class="ctrl ctrl-lg">
            <input type="number" data-drawer-h="${i}" min="0" max="60" value="${cm}"/>
            <span class="unit">سم</span>
            <div class="steppers">
              <button type="button" data-drawer-h-step="${i}" data-dir="1">▲</button>
              <button type="button" data-drawer-h-step="${i}" data-dir="-1">▼</button>
            </div>
          </div>
        </div>`;
    }
    return html;
  }

  function doorOption(id, labelAr, labelEn, kind, disabled) {
    const svg = {
      left:   `<svg viewBox="0 0 40 46" width="32" height="36"><rect x="5" y="3" width="30" height="40" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="29" cy="23" r="1.2" fill="currentColor"/></svg>`,
      right:  `<svg viewBox="0 0 40 46" width="32" height="36"><rect x="5" y="3" width="30" height="40" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="11" cy="23" r="1.2" fill="currentColor"/></svg>`,
      double: `<svg viewBox="0 0 40 46" width="32" height="36"><rect x="3" y="3" width="16" height="40" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="21" y="3" width="16" height="40" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.6"/><circle cx="17" cy="23" r="1" fill="currentColor"/><circle cx="23" cy="23" r="1" fill="currentColor"/></svg>`
    }[kind];
    const active = state.settings.doorType === id ? 'active' : '';
    const dA = disabled ? 'disabled' : '';
    const dS = disabled ? 'opacity:.35;cursor:not-allowed;' : '';
    return `
      <button class="door-opt ${active}" data-door="${id}" ${dA} style="${dS}">
        <span class="dot"></span>
        <div class="ico">${svg}</div>
        <b>${labelAr}</b>
        <em>${labelEn}</em>
      </button>`;
  }

  function ovenDrawerOption(id, labelAr, labelEn, iconKey) {
    const active = state.settings.ovenDrawer === id ? 'active' : '';
    return `
      <button class="door-opt ${active}" data-oven-drawer="${id}">
        <span class="dot"></span>
        <div class="ico">${icons[iconKey] || icons.cube}</div>
        <b>${labelAr}</b>
        <em>${labelEn}</em>
      </button>`;
  }

  function ovenBoxOption(id, labelAr, labelEn, iconKey) {
    const isWith = state.settings.ovenDrawerBox;
    const isActive = (id === 'with' && isWith) || (id === 'without' && !isWith);
    const active = isActive ? 'active' : '';
    return `
      <button class="door-opt ${active}" data-oven-box="${id}">
        <span class="dot"></span>
        <div class="ico">${icons[iconKey] || icons.cube}</div>
        <b>${labelAr}</b>
        <em>${labelEn}</em>
      </button>`;
  }

  function dimField(key, label, valueMm) {
    const cmValue = mmToCm(valueMm);
    return `
      <div class="dim-field">
        <div class="dim-field-label"><span>${label}</span><span class="ar">cm</span></div>
        <div class="ctrl ctrl-lg">
          <input type="number" data-field="${key}" min="20" max="300" value="${cmValue}"/>
          <span class="unit">سم</span>
          <div class="steppers">
            <button type="button" data-step-field="${key}" data-dir="1">▲</button>
            <button type="button" data-step-field="${key}" data-dir="-1">▼</button>
          </div>
        </div>
      </div>`;
  }

  function configRow(ico, label, value) {
    return `
      <div class="config-row">
        <span class="ico">${ico}</span>
        <span class="label">${label}</span>
        <span class="val">${value}</span>
      </div>`;
  }

  function renderStylesTab() {
    const list = state.stylesList || { presets: [], custom: [], current: null };
    return `
      <div class="styles-header">
        <h2>الأنماط والتشطيبات</h2>
        <p class="dim-desc">اختر نمطاً لتطبيقه على الوحدة المحددة</p>
      </div>
      <div class="styles-section">
        <h3>الأنماط الجاهزة</h3>
        <div class="styles-grid">
          ${list.presets.length > 0 ? list.presets.map(styleCard).join('') :
            '<p style="color:var(--text-3);text-align:center;padding:20px;">جاري التحميل...</p>'}
        </div>
      </div>
      ${list.custom && list.custom.length > 0 ? `
        <div class="styles-section">
          <h3>أنماط مخصصة</h3>
          <div class="styles-grid">${list.custom.map(styleCard).join('')}</div>
        </div>` : ''}
      <div class="styles-section">
        <button class="btn btn-secondary" id="newStyleBtn" style="width:100%;">
          ${icons.plus} إضافة نمط مخصص
        </button>
      </div>
    `;
  }

  function styleCard(style) {
    const isCurrent = style.is_current;
    const colors = (style.colors && style.colors.length > 0) ? style.colors : ['#cccccc', '#aaaaaa', '#888888'];
    const hasTexture = !!style.texture_url;
    const previewHTML = hasTexture
      ? `<div class="preview-texture" style="background-image:url('${style.texture_url}');"></div>`
      : colors.map(c => `<div class="preview-strip" style="background:${c};"></div>`).join('');
    return `
      <div class="style-card ${isCurrent ? 'current' : ''}" data-style-id="${style.id}">
        <div class="style-preview ${hasTexture ? 'has-texture' : ''}">${previewHTML}</div>
        <div class="style-info">
          <h4>${style.name}</h4>
          <div class="style-name-ar">${style.name_ar}</div>
          <p>${style.desc || ''}</p>
        </div>
        <div class="style-actions">
          ${isCurrent ? `<span class="style-badge-current">✓ مفعل</span>` :
            `<button class="apply-style-btn" data-apply-style="${style.id}">تطبيق</button>`}
        </div>
      </div>`;
  }

  function renderStylesPanel() {
    return `
      <div class="config-card">
        <h3>${icons.brush} عن الأنماط</h3>
        <p style="font-size:11.5px;color:var(--text-3);line-height:1.6;">
          • حدد وحدة في المشهد.<br>
          • اختر نمطاً من الوسط.<br>
          • اضغط "تطبيق".<br>
          • يمكنك إضافة نمط مخصص بالأسفل.
        </p>
      </div>`;
  }

  function ensureCustomStyleModal() {
    if (document.getElementById('cnModalOverlay')) return;
    const overlay = document.createElement('div');
    overlay.id = 'cnModalOverlay';
    overlay.className = 'cn-modal-overlay';
    overlay.innerHTML = `
      <div class="cn-modal">
        <div class="cn-modal-header">
          <h3>إضافة نمط مخصص</h3>
          <button type="button" class="cn-modal-close" id="cnModalClose">✕</button>
        </div>
        <div class="cn-modal-body">
          <div class="form-row">
            <div class="form-group"><label>الاسم بالإنجليزية</label><input type="text" id="csName" placeholder="Custom Style"/></div>
            <div class="form-group"><label>الاسم بالعربية</label><input type="text" id="csNameAr" placeholder="نمط مخصص"/></div>
          </div>
          <div class="form-group"><label>الوصف</label><input type="text" id="csDesc" placeholder="وصف مختصر للنمط"/></div>
          <div class="form-section"><h4>مادة الدرف</h4><select id="csDoorMat"></select></div>
          <div class="form-section"><h4>مادة العلب والأرضية والأرفف</h4><select id="csCarcassMat"></select></div>
          <div class="form-section"><h4>حاشية الدرف</h4><select id="csDoorEdge"></select></div>
          <div class="form-section"><h4>حاشية العلب</h4><select id="csCarcassEdge"></select></div>
        </div>
        <div class="cn-modal-footer">
          <button type="button" class="btn btn-secondary" id="csCancel">إلغاء</button>
          <button type="button" class="btn btn-primary" id="csSave">حفظ النمط</button>
        </div>
      </div>`;
    document.body.appendChild(overlay);
    $('#cnModalClose')?.addEventListener('click', closeCustomStyleModal);
    $('#csCancel')?.addEventListener('click', closeCustomStyleModal);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) closeCustomStyleModal(); });
    $('#csSave')?.addEventListener('click', onSaveCustomStyle);
  }

  function openCustomStyleModal() {
    ensureCustomStyleModal();
    $('#csName').value = ''; $('#csNameAr').value = ''; $('#csDesc').value = '';
    $('#cnModalOverlay').classList.add('visible');
    state.materialsList = null;
    populateMaterialDropdowns();
    bridge.call('list_available_materials');
  }

  function closeCustomStyleModal() {
    const overlay = $('#cnModalOverlay');
    if (overlay) overlay.classList.remove('visible');
  }

  function populateMaterialDropdowns() {
    const list = state.materialsList;
    const doorSel = $('#csDoorMat'), carcassSel = $('#csCarcassMat');
    const doorEdgeSel = $('#csDoorEdge'), carcassEdgeSel = $('#csCarcassEdge');
    if (!doorSel || !carcassSel || !doorEdgeSel || !carcassEdgeSel) return;
    if (!list) {
      const loading = '<option value="">— جاري التحميل... —</option>';
      doorSel.innerHTML = loading; carcassSel.innerHTML = loading;
      doorEdgeSel.innerHTML = loading; carcassEdgeSel.innerHTML = loading;
      return;
    }
    const boards = list.boards || [];
    const edges  = list.edges  || [];
    if (boards.length === 0) {
      const empty = '<option value="">— لا توجد مواد —</option>';
      doorSel.innerHTML = empty; carcassSel.innerHTML = empty;
    } else {
      const opts = boards.map(b => `<option value="${b.name}">${b.name}</option>`).join('');
      doorSel.innerHTML = opts; carcassSel.innerHTML = opts;
    }
    if (edges.length === 0) {
      const empty = '<option value="">— لا توجد حواشي —</option>';
      doorEdgeSel.innerHTML = empty; carcassEdgeSel.innerHTML = empty;
    } else {
      const opts = edges.map(e => `<option value="${e.name}">${e.name}</option>`).join('');
      doorEdgeSel.innerHTML = opts; carcassEdgeSel.innerHTML = opts;
    }
  }

  function onSaveCustomStyle() {
    const name = $('#csName')?.value.trim();
    const nameAr = $('#csNameAr')?.value.trim() || name;
    const desc = $('#csDesc')?.value.trim() || '';
    const doorMat = $('#csDoorMat')?.value;
    const carcassMat = $('#csCarcassMat')?.value;
    const doorEdge = $('#csDoorEdge')?.value;
    const carcassEdge = $('#csCarcassEdge')?.value;
    if (!name) { showToast('❌ أدخل الاسم بالإنجليزية', 'err'); return; }
    if (!doorMat || !carcassMat) { showToast('❌ اختر مواد الدرف والعلب', 'err'); return; }
    if (!doorEdge || !carcassEdge) { showToast('❌ اختر الحواشي', 'err'); return; }
    const id = 'custom_' + Date.now();
    const styleData = {
      id, name, name_ar: nameAr, desc,
      colors: ['#c2d8ff', '#cccccc', '#888888'],
      surface: {
        carcass: { material: carcassMat }, door: { material: doorMat },
        back: { material: 'ظهور بورديوم 6مملي' }, shelf: { material: carcassMat },
        plinth: { material: 'اكسسوار' }, handle: { material: 'مقبض حرف L اسود' }
      },
      edges: {
        floor: { front: carcassEdge, back: 'مفحار1', left: carcassEdge, right: carcassEdge },
        side: { front: carcassEdge, back: 'مفحار1', top: carcassEdge },
        shelf: { front: carcassEdge },
        front_rail: { front: carcassEdge, back: carcassEdge },
        back_rail: { top: carcassEdge },
        door: { left: doorEdge, right: doorEdge, top: doorEdge, bottom: doorEdge }
      }
    };
    bridge.call('save_style', JSON.stringify(styleData));
    closeCustomStyleModal();
  }

  function render() {
    const main  = $('#mainPanel');
    const right = $('#rightPanel');
    if (state.tab === 'cabinets') {
      main.innerHTML  = renderCabinetsTab();
      right.innerHTML = renderRightPanel();
      bindCabinetEvents();
    } else if (state.tab === 'styles') {
      main.innerHTML  = renderStylesTab();
      right.innerHTML = renderStylesPanel();
      bindStyleEvents();
    } else {
      main.innerHTML  = `<section class="panel-card"><h2>التصنيع والتقارير</h2><p>قريباً</p></section>`;
      right.innerHTML = '';
    }
  }

  // ----- قائمة نقل الوحدة بين التصنيفات -----
  function closeMoveMenu() { document.getElementById('libMoveMenu')?.remove(); }
  function openMoveMenu(itemId, anchor) {
    closeMoveMenu();
    const cur = effectiveGroupId(itemId, originalGroupOf(itemId));
    const orig = originalGroupOf(itemId);
    const menu = document.createElement('div');
    menu.id = 'libMoveMenu';
    menu.className = 'lib-move-menu';
    menu.innerHTML = `
      <div class="lmm-title">${isEn() ? 'Move to category' : 'نقل إلى تصنيف'}</div>
      ${LIBRARY_GROUPS.map(g => `
        <button type="button" class="lmm-item ${g.id === cur ? 'current' : ''}" data-to="${g.id}">
          <span class="lmm-ico">${g.icon}</span><span>${groupTitle(g)}</span>${g.id === cur ? '<i>✓</i>' : ''}
        </button>`).join('')}
      ${cur !== orig ? `<button type="button" class="lmm-item reset" data-to="${orig}">↺ ${isEn() ? 'Back to original' : 'إرجاع للتصنيف الأصلي'}</button>` : ''}
    `;
    document.body.appendChild(menu);
    const r = anchor.getBoundingClientRect();
    const mw = menu.offsetWidth, mh = menu.offsetHeight;
    let left = r.left; let top = r.bottom + 6;
    if (left + mw > window.innerWidth - 8) left = window.innerWidth - mw - 8;
    if (left < 8) left = 8;
    if (top + mh > window.innerHeight - 8) top = Math.max(8, r.top - mh - 6);
    menu.style.left = left + 'px'; menu.style.top = top + 'px';
    menu.querySelectorAll('[data-to]').forEach(b => b.addEventListener('click', (e) => {
      e.stopPropagation();
      closeMoveMenu();
      moveItemToGroup(itemId, b.getAttribute('data-to'));
    }));
  }
  if (!window.__cnMoveBound) {
    window.__cnMoveBound = true;
    document.addEventListener('click', (e) => {
      const mv = e.target.closest && e.target.closest('[data-move]');
      if (mv) { e.preventDefault(); e.stopPropagation(); openMoveMenu(mv.getAttribute('data-move'), mv); return; }
      if (!(e.target.closest && e.target.closest('#libMoveMenu'))) closeMoveMenu();
    }, true);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeMoveMenu(); });
  }

  // ----- سحب وإفلات الكروت على التصنيفات -----
  function bindLibraryDnD() {
    $$('#libGridContainer .lib-card[draggable="true"]').forEach(card => {
      card.addEventListener('dragstart', (e) => {
        closeMoveMenu();
        card.classList.add('dragging');
        e.dataTransfer.setData('text/plain', card.getAttribute('data-preset'));
        e.dataTransfer.effectAllowed = 'move';
      });
      card.addEventListener('dragend', () => {
        card.classList.remove('dragging');
        $$('#libGridContainer .lib-group').forEach(g => g.classList.remove('drop-hover'));
      });
    });
    $$('#libGridContainer .lib-group').forEach(sec => {
      sec.addEventListener('dragover', (e) => { e.preventDefault(); sec.classList.add('drop-hover'); });
      sec.addEventListener('dragleave', (e) => { if (!sec.contains(e.relatedTarget)) sec.classList.remove('drop-hover'); });
      sec.addEventListener('drop', (e) => {
        e.preventDefault();
        sec.classList.remove('drop-hover');
        const id = e.dataTransfer.getData('text/plain');
        const gid = sec.getAttribute('data-group');
        if (id && LIBRARY_GROUPS.some(g => g.id === gid)) moveItemToGroup(id, gid);
      });
    });
  }

  function bindPresetCard(btn) {
    let timer = null;
    btn.addEventListener('click', () => {
      clearTimeout(timer);
      timer = setTimeout(() => { applyPreset(btn.getAttribute('data-preset')); }, 220);
    });
    btn.addEventListener('dblclick', () => {
      clearTimeout(timer);
      applyPreset(btn.getAttribute('data-preset'));
      setTimeout(() => { if (typeof onCreateCabinet === 'function') onCreateCabinet(); }, 60);
    });
  }

  function refreshLibraryGrid() {
    const container = $('#libGridContainer');
    if (!container) return;
    container.innerHTML = renderLibraryGrid();
    $$('#libGridContainer [data-preset]').forEach(btn => bindPresetCard(btn));
    bindLibraryDnD();
    $('#libResetBtn')?.addEventListener('click', () => {
      state.libSearch = ''; state.libFilter = 'all'; refreshLibraryUI();
    });
    const res = $('#libResults');
    if (res) res.textContent = resultsText(getFilteredCount());
    $$('#mainPanel .lib-chip').forEach(chip => {
      const id = chip.getAttribute('data-filter');
      chip.classList.toggle('active', state.libFilter === id);
    });
  }

  function refreshLibraryUI() {
    const input = $('#libSearchInput');
    if (input && input.value !== state.libSearch) input.value = state.libSearch;
    const clear = $('#libSearchClear');
    if (clear) clear.style.display = state.libSearch ? 'inline-flex' : 'none';
    refreshLibraryGrid();
  }

  function bindCabinetEvents() {
    const searchInput = $('#libSearchInput');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        state.libSearch = e.target.value;
        refreshLibraryUI();
      });
    }

    $('#libSearchClear')?.addEventListener('click', () => {
      state.libSearch = ''; refreshLibraryUI(); $('#libSearchInput')?.focus();
    });

    $('#libResetBtn')?.addEventListener('click', () => {
      state.libSearch = ''; state.libFilter = 'all'; refreshLibraryUI();
    });

    $$('#mainPanel .lib-chip').forEach(chip => {
      chip.addEventListener('click', () => {
        state.libFilter = chip.getAttribute('data-filter');
        refreshLibraryUI();
      });
    });

    $('#wallBackBtn')?.addEventListener('click', () => setNav('library'));
    $$('#libGridContainer [data-preset]').forEach(btn => bindPresetCard(btn));
    bindLibraryDnD();

    // ---- الأبعاد العامة ----
    $$('#rightPanel input[data-field]').forEach(inp => {
      inp.addEventListener('change', () => {
        const key = inp.getAttribute('data-field');
        let cm = parseInt(inp.value, 10);
        if (isNaN(cm) || cm < 20) cm = 20;
        if (cm > 300) cm = 300;
        state.settings[key] = cmToMm(cm);
        inp.value = cm;
        if (key === 'width' && enforceDoorType()) { render(); return; }
        refreshRightPanel();
      });
    });

    $$('#rightPanel [data-step-field]').forEach(btn => {
      btn.addEventListener('click', () => {
        const key = btn.getAttribute('data-step-field');
        const dir = parseInt(btn.getAttribute('data-dir'), 10);
        let cm = mmToCm(state.settings[key]) + dir;
        if (cm < 20) cm = 20;
        if (cm > 300) cm = 300;
        state.settings[key] = cmToMm(cm);
        const inp = $(`#rightPanel input[data-field="${key}"]`);
        if (inp) inp.value = cm;
        if (key === 'width' && enforceDoorType()) { render(); return; }
        refreshRightPanel();
      });
    });

    const shel = $('#shelvesInput');
    if (shel) {
      shel.addEventListener('change', () => {
        state.settings.shelves = Math.max(0, Math.min(8, parseInt(shel.value, 10) || 0));
        shel.value = state.settings.shelves;
      });
      $$('#rightPanel [data-step]').forEach(b => {
        b.addEventListener('click', () => {
          const dir = parseInt(b.getAttribute('data-step'), 10);
          state.settings.shelves = Math.max(0, Math.min(8, state.settings.shelves + dir));
          shel.value = state.settings.shelves;
        });
      });
    }

    const dcInput = $('#drawerCountInput');
    if (dcInput) {
      dcInput.addEventListener('change', () => {
        let n = parseInt(dcInput.value, 10);
        if (isNaN(n) || n < 1) n = 1;
        if (n > 6) n = 6;
        state.settings.drawerCount = n;
        state.settings.drawerHeights = computeDrawerHeights(state.settings, 'target', 360);
        render();
      });
      $$('#rightPanel [data-drawer-step]').forEach(b => {
        b.addEventListener('click', () => {
          const dir = parseInt(b.getAttribute('data-drawer-step'), 10);
          let n = state.settings.drawerCount + dir;
          if (n < 1) n = 1;
          if (n > 6) n = 6;
          state.settings.drawerCount = n;
          state.settings.drawerHeights = computeDrawerHeights(state.settings, 'target', 360);
          render();
        });
      });
    }

    $$('#rightPanel input[data-drawer-h]').forEach(inp => {
      inp.addEventListener('change', () => {
        const i = parseInt(inp.getAttribute('data-drawer-h'), 10);
        let cm = parseInt(inp.value, 10);
        if (isNaN(cm) || cm < 0) cm = 0;
        if (cm > 60) cm = 60;
        state.settings.drawerHeights[i] = cmToMm(cm);
        inp.value = cm;
        render();
      });
    });

    $$('#rightPanel [data-drawer-h-step]').forEach(btn => {
      btn.addEventListener('click', () => {
        const i = parseInt(btn.getAttribute('data-drawer-h-step'), 10);
        const dir = parseInt(btn.getAttribute('data-dir'), 10);
        let cm = mmToCm(state.settings.drawerHeights[i] || 0) + dir;
        if (cm < 0) cm = 0;
        if (cm > 60) cm = 60;
        state.settings.drawerHeights[i] = cmToMm(cm);
        const inp = $(`#rightPanel input[data-drawer-h="${i}"]`);
        if (inp) inp.value = cm;
        render();
      });
    });

    $$('#doorGrid .door-opt').forEach(btn => {
      if (btn.hasAttribute('disabled')) return;
      btn.addEventListener('click', () => {
        state.settings.doorType = btn.getAttribute('data-door');
        render();
      });
    });

    $$('#ovenDrawerGrid .door-opt').forEach(btn => {
      btn.addEventListener('click', () => {
        state.settings.ovenDrawer = btn.getAttribute('data-oven-drawer');
        render();
      });
    });

    $$('#ovenBoxGrid .door-opt').forEach(btn => {
      btn.addEventListener('click', () => {
        state.settings.ovenDrawerBox = (btn.getAttribute('data-oven-box') === 'with');
        render();
      });
    });

    $$('#cfSideGrid .door-opt').forEach(btn => {
      btn.addEventListener('click', () => {
        state.settings.fixedSide = btn.getAttribute('data-cf-side');
        render();
      });
    });

    // ⭐⭐⭐ جديد: قسم دولاب الفرن - اختيار القسم السفلي
    $$('#tallBottomGrid .door-opt').forEach(btn => {
      btn.addEventListener('click', () => {
        state.settings.tallBottomType = btn.getAttribute('data-tall-bottom');
        render();
      });
    });

    // ⭐⭐⭐ دولاب التخزين
    $$('#tsLayoutGrid [data-ts-layout]').forEach(btn => {
      btn.addEventListener('click', () => {
        const v = btn.getAttribute('data-ts-layout');
        state.settings.tsLayout = v;
        if (v === 'door_flip') state.settings.tsSplitH = 1700;
        else if (v === 'two_doors') state.settings.tsSplitH = 1200;
        render();
      });
    });
    $$('#tsHandlesGrid [data-ts-handles]').forEach(btn => {
      btn.addEventListener('click', () => {
        state.settings.tsHandles = btn.getAttribute('data-ts-handles') === 'yes';
        render();
      });
    });
    $$('#rightPanel input[data-ts-field]').forEach(inp => {
      inp.addEventListener('change', () => {
        const key = inp.getAttribute('data-ts-field');
        const max = parseInt(inp.getAttribute('max'), 10) || 300;
        let cm = parseFloat(inp.value);
        if (isNaN(cm) || cm < 0) cm = 0;
        if (cm > max) cm = max;
        state.settings[key] = Math.round(cm * 10);
        inp.value = Math.round(cm);
        refreshRightPanel();
      });
    });
    $$('#rightPanel [data-ts-step]').forEach(btn => {
      btn.addEventListener('click', () => {
        const key = btn.getAttribute('data-ts-step');
        const dir = parseInt(btn.getAttribute('data-dir'), 10);
        const max = parseInt(btn.getAttribute('data-max'), 10) || 300;
        let cm = mmToCm(state.settings[key] || 0) + dir * 5;
        cm = Math.max(0, Math.min(max, cm));
        state.settings[key] = cmToMm(cm);
        refreshRightPanel();
      });
    });
    $$('#rightPanel [data-ts-clear]').forEach(btn => {
      btn.addEventListener('click', () => {
        state.settings.tsClearH = parseInt(btn.getAttribute('data-ts-clear'), 10) || 0;
        refreshRightPanel();
      });
    });
    const tsShel = $('#tsShelvesInput');
    if (tsShel) {
      tsShel.addEventListener('change', () => {
        state.settings.tsShelves = Math.max(0, Math.min(12, parseInt(tsShel.value, 10) || 0));
        tsShel.value = state.settings.tsShelves;
      });
      $$('#rightPanel [data-ts-shelves-step]').forEach(b => {
        b.addEventListener('click', () => {
          const dir = parseInt(b.getAttribute('data-ts-shelves-step'), 10);
          state.settings.tsShelves = Math.max(0, Math.min(12, state.settings.tsShelves + dir));
          tsShel.value = state.settings.tsShelves;
        });
      });
    }
    const tsDn = $('#tsDrawerNInput');
    if (tsDn) {
      const setN = (n) => { state.settings.tsDrawerN = Math.max(0, Math.min(4, n)); render(); };
      tsDn.addEventListener('change', () => setN(parseInt(tsDn.value, 10) || 0));
      $$('#rightPanel [data-ts-drawern-step]').forEach(b => {
        b.addEventListener('click', () => setN((state.settings.tsDrawerN || 0) + parseInt(b.getAttribute('data-ts-drawern-step'), 10)));
      });
    }
    const tsPos = $('#tsShelfPosInput');
    if (tsPos) tsPos.addEventListener('change', () => { state.settings.tsShelfPos = tsPos.value; });

    $('#createBtn')?.addEventListener('click', onCreateCabinet);
    $('#saveBtn')?.addEventListener('click', onSaveSettings);
  }

  function bindStyleEvents() {
    $$('#mainPanel [data-apply-style]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const styleId = btn.getAttribute('data-apply-style');
        btn.disabled = true;
        btn.textContent = 'جاري التطبيق...';
        bridge.call('apply_style', styleId);
      });
    });
    $('#newStyleBtn')?.addEventListener('click', openCustomStyleModal);
  }

  function refreshRightPanel() {
    if (state.tab === 'cabinets') {
      $('#rightPanel').innerHTML = renderRightPanel();
      bindCabinetEvents();
    }
  }

  // ⭐⭐⭐ محدّث: إرسال tall_bottom_type
  function onCreateCabinet() {
    enforceDoorType();
    const s = state.settings;
    const heights = (s.drawerHeights || []).slice(0, s.drawerCount).map(h => h || 0);
    bridge.call('create_cabinet',
      String(s.width), String(s.height), String(s.depth),
      s.doorType, String(s.shelves), s.unitSubtype,
      s.ovenDrawer, String(s.ovenDrawerBox), String(s.ovenVent),
      JSON.stringify(heights),
      String(s.cornerWRight || 900),
      String(s.cornerWLeft  || 900),
      String(s.cornerDRight || 580),
      String(s.cornerDLeft  || 580),
      String(s.fixedSide    || 'left'),
      String(s.counterWidth || 500),
      String(s.fillerWidth  || 150),
      String(s.tallBottomType || 'drawers'),  // ⭐ جديد
      String(s.tallBottomH || 620),
      String(s.tallOvenH   || 600),
      String(s.tallMicroH  || 450),
      JSON.stringify(tsPayload(s))
    );
  }

  function onSaveSettings() {
    bridge.call('save_settings', JSON.stringify(state.settings));
    showToast('تم حفظ الإعدادات');
  }

  function bindHeader() {
    $$('.lang-toggle button').forEach(btn => {
      btn.addEventListener('click', () => setLanguage(btn.getAttribute('data-lang')));
    });
    // التصغير: delegation على الـ document عشان يشتغل حتى لو الزرار اتعاد رسمه أو اتغير شكله
    if (!window.__cnMinBound) {
      window.__cnMinBound = true;
      document.addEventListener('click', (ev) => {
        const t = ev.target && ev.target.closest
          ? ev.target.closest('#wcMin, [data-action="minimize"], [aria-label="تصغير"], [title="تصغير النافذة"]')
          : null;
        if (!t) return;
        ev.preventDefault();
        const next = !document.body.classList.contains('collapsed');
        document.body.classList.toggle('collapsed', next);
        const ok = bridge.call('minimize_dialog', next ? 'true' : 'false');
        if (!ok) bridge.call('log', 'minimize_dialog callback missing');
      }, true);
    }
    $('#wcClose')?.addEventListener('click', () => bridge.call('close_dialog'));

    // زرار القائمة العائمة (التالت في الهيدر): أي زرار في window-controls غير التصغير والإغلاق
    // ومالوش onclick/data-action خاص بيه → بيفتح/يقفل القائمة العائمة
    if (!window.__cnFtbBound) {
      window.__cnFtbBound = true;
      document.addEventListener('click', (ev) => {
        const b = ev.target && ev.target.closest ? ev.target.closest('.window-controls button') : null;
        if (!b) return;
        if (b.id === 'wcMin' || b.id === 'wcClose' || b.classList.contains('wc-close')) return;
        if (b.hasAttribute('onclick') || b.hasAttribute('data-action')) return;
        ev.preventDefault();
        if (!bridge.call('toggle_floating_toolbar')) bridge.call('log', 'toggle_floating_toolbar callback missing');
      }, true);
    }
  }

  // ===== الترجمة الإنجليزية: العناصر الثابتة (data-i18n) + ترجمة DOM للباقي =====
  const EN_PHRASES = {
    'الارتفاع الافتراضي 78 لكل الوحدات ما عدا دولاب الفرن': 'Default height 78 for all units except the tall oven',
    'الاتجاه بيطبّق على الدرف المفصلية (القلاب بيفتح لفوق)': 'Direction applies to hinged doors (the flip-up opens upward)',
    'مواضع الرفوف يدوي (اختياري)': 'Manual shelf positions (optional)',
    'مواضع الرفوف يدوي': 'Manual shelf positions',
    'لو كتبت مواضع، بتتجاهل العدد والفراغ السفلي': 'If positions are entered, the count and bottom clearance are ignored',
    'فراغ سفلي بدون رفوف (للمقاشات والنضافة)': 'Bottom clearance with no shelves (for brooms & cleaning)',
    '0 = توزيع عادي — أول رف بيبدأ عند نهاية الفراغ': '0 = normal spacing — first shelf starts at the end of the clearance',
    'كل المقاسات من الأرض (بما فيها الرجل)': 'All heights measured from the floor (including legs)',
    'ارتفاع الفاصل بين الدرفتين (من الأرض)': 'Split height between the doors (from floor)',
    'ارتفاع الدرفة السفلية (من الأرض)': 'Lower door height (from floor)',
    'ارتفاع الفاصل بين الدرفتين / القلاب': 'Split height between doors / flip-up',
    'وش بدون فتحات — اختر شكل الأوجه': 'Plain fronts (no openings) — choose the front layout',
    'العرض الافتراضي 60 ما عدا السدة': 'Default width 60 except the counter filler',
    'الأبعاد الافتراضية (بالسنتيمتر)': 'Default dimensions (centimetres)',
    'مادة العلب والأرضية والأرفف': 'Box, floor and shelf material',
    'عدد الأدراج السفلية': 'Bottom drawers count',
    'بدون أدراج (حتى 4)': 'No drawers (up to 4)',
    'ارتفاع كل درج': 'Height of each drawer',
    'اختر نوع الأبواب لخزانتك': 'Choose the door type for your cabinet',
    'اختر مواد الدرف والعلب': 'Choose door and box materials',
    'اختر نمطاً لتطبيقه على الوحدة المحددة': 'Pick a style to apply to the selected unit',
    'يمكنك إضافة نمط مخصص بالأسفل': 'You can add a custom style below',
    'اختر الحواشي': 'Choose edge banding',
    'توزيع تلقائي حسب ارتفاع الوحدة': 'Automatic, based on unit height',
    'الدرفة العلوية (تلقائي)': 'Upper door (automatic)',
    'القسم السفلي (أدراج / درف)': 'Bottom section (drawers / doors)',
    'ارتفاع القسم السفلي لدولاب الفرن': 'Bottom section height of the tall oven',
    'ارتفاع فتحة الفرن': 'Oven opening height',
    'ارتفاع درفة الميكروويف': 'Microwave door height',
    'موضع الدرج في وحدة الفرن': 'Drawer position in the oven unit',
    'اختر أين يوضع الدرج بالنسبة للفرن': 'Choose where the drawer sits relative to the oven',
    'مقابض C و L': 'C & L handles',
    'بدون مقابض (لمس)': 'No handles (push-to-open)',
    'بدون (لمس)': 'None (push)',
    'درفة سفلية + قلاب': 'Lower door + flip-up',
    'درج سفلي + درفة': 'Bottom drawer + door',
    'درفتين فوق بعض': 'Stacked doors',
    'درفة / درفتين': 'Door / double doors',
    'درفة طويلة': 'Full-height door',
    'دواليب التخزين': 'Tall Storage',
    'دولاب التخزين': 'Tall Storage',
    'دولاب تخزين': 'Tall Storage',
    'دولاب فرن': 'Tall Oven',
    'وحدات خاصة': 'Special Units',
    'الأنماط والتشطيبات': 'Styles & Finishes',
    'التصنيع والتقارير': 'Manufacturing & Reports',
    'مكتبة الخزائن': 'Cabinets Library',
    'التكوين الحالي': 'Current configuration',
    'شكل الأوجه': 'Front layout',
    'نوع الوحدة': 'Unit type',
    'اتجاه الفتح': 'Opening direction',
    'موضع الدرج': 'Drawer position',
    'عدد الرفوف': 'Number of shelves',
    'عدد الأرفف': 'Number of shelves',
    'الرفوف الداخلية': 'Internal shelves',
    'فراغ سفلي': 'Bottom clearance',
    'مواضع يدوية': 'Manual positions',
    'توزيع عادي': 'Normal spacing',
    'بدون فراغ': 'No clearance',
    'سماكة الجانب (مقفل)': 'Side thickness (locked)',
    'سماكة الجانب (مفعل)': 'Side thickness (enabled)',
    'الأبعاد العامة': 'General dimensions',
    'الأبعاد': 'Dimensions',
    'الارتفاع': 'Height',
    'العرض': 'Width',
    'العمق': 'Depth',
    'تكوينات الأبواب': 'Door layouts',
    'تكوينات أبواب الحوض': 'Sink door layouts',
    'تكوين الأدراج': 'Drawer layout',
    'المقابض': 'Handles',
    'بمقابض': 'With handles',
    'بدون': 'None',
    'باب يمين': 'Right door',
    'باب يسار': 'Left door',
    'بابان': 'Double doors',
    'درفة يمين': 'Right door',
    'درفة شمال': 'Left door',
    'درفتين': 'Double doors',
    'درفة': 'Door',
    'الأبواب': 'Doors',
    'الأدراج': 'Drawers',
    'أدراج': 'Drawers',
    'درجين': 'Two drawers',
    'درج واحد': 'One drawer',
    'أدراج متساوية': 'Equal drawers',
    'درجان متساويين': 'Two equal drawers',
    'صغير + 2 وسط': 'Small + 2 medium',
    'تحت الفرن': 'Below the oven',
    'فوق الفرن': 'Above the oven',
    'تحت': 'Below',
    'فوق': 'Above',
    'سدة كونتر': 'Counter filler',
    'وحدة حوض': 'Sink unit',
    'وحدة فرن': 'Oven unit',
    'كورنر L': 'L-Corner',
    'كورنر': 'Corner',
    'إنشاء خزانة': 'Create cabinet',
    'حفظ الإعدادات': 'Save settings',
    'تم حفظ الإعدادات': 'Settings saved',
    'تم إنشاء': 'Created',
    'فشل الإنشاء': 'Creation failed',
    'جاري التحميل': 'Loading',
    'مسح البحث': 'Clear search',
    'تطبيق': 'Apply',
    'إلغاء': 'Cancel',
    'قريباً': 'Coming soon',
    'الاسم بالعربية': 'Arabic name',
    'الاسم بالإنجليزية': 'English name',
    'نمط مخصص': 'Custom style',
    'أنماط مخصصة': 'Custom styles',
    'الأنماط الجاهزة': 'Preset styles',
    'مادة الدرف': 'Door material',
    'حاشية الدرف': 'Door edge banding',
    'حاشية العلب': 'Box edge banding',
    'اكسسوار': 'Accessory',
    'مفعل': 'Enabled',
    'جديد': 'New',
    'الكل': 'All',
    'سم': 'cm',
    'مم': 'mm'
  };
  const EN_KEYS = Object.keys(EN_PHRASES).sort((a, b) => b.length - a.length);
  const AR_RE = /[\u0600-\u06FF]/;
  function trEn(str) {
    if (!AR_RE.test(str)) return str;
    const t = str.trim();
    if (EN_PHRASES[t]) return str.replace(t, EN_PHRASES[t]);
    let out = str;
    for (const k of EN_KEYS) { if (out.indexOf(k) !== -1) out = out.split(k).join(EN_PHRASES[k]); }
    return out;
  }
  let __trBusy = false;
  function translateTree(root) {
    if (!isEn() || !root) return;
    __trBusy = true;
    try {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode: (n) => (n.parentNode && /^(SCRIPT|STYLE)$/.test(n.parentNode.nodeName)) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
      });
      const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
      nodes.forEach(n => { const v = trEn(n.nodeValue); if (v !== n.nodeValue) n.nodeValue = v; });
      const els = root.querySelectorAll ? root.querySelectorAll('[placeholder],[title],[aria-label]') : [];
      els.forEach(el => ['placeholder', 'title', 'aria-label'].forEach(a => {
        const v = el.getAttribute(a); if (v && AR_RE.test(v)) el.setAttribute(a, trEn(v));
      }));
    } finally { __trBusy = false; }
  }
  function applyStaticI18n(lang) {
    $$('[data-i18n]').forEach(el => {
      if (el.dataset.i18nAr === undefined) el.dataset.i18nAr = el.textContent;
      el.textContent = lang === 'en' ? i18n.t(el.getAttribute('data-i18n')) : el.dataset.i18nAr;
    });
    // الزرار التالت في الهيدر: تلميح واضح
    $$('.window-controls button').forEach(b => {
      if (b.id === 'wcMin') b.title = lang === 'en' ? 'Minimize' : 'تصغير النافذة';
      else if (b.id === 'wcClose' || b.classList.contains('wc-close')) b.title = lang === 'en' ? 'Close' : 'إغلاق';
      else b.title = lang === 'en' ? 'Floating toolbar' : 'القائمة العائمة';
    });
  }
  function setupTranslator() {
    const mo = new MutationObserver(() => {
      if (__trBusy || !isEn()) return;
      mo.disconnect();
      translateTree(document.body);
      mo.observe(document.body, { childList: true, subtree: true, characterData: true });
    });
    mo.observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  function setLanguage(lang) {
    state.lang = lang;
    i18n.setLang(lang === 'en' ? 'en' : 'en');   // dict فيه en بس؛ العربي بيرجع من النص الأصلي
    document.documentElement.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
    document.documentElement.setAttribute('lang', lang);
    document.body.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
    document.body.classList.toggle('lang-en', lang === 'en');
    $$('.lang-toggle button').forEach(b => b.classList.toggle('active', b.getAttribute('data-lang') === lang));
    applyStaticI18n(lang);
    render();
    translateTree(document.body);
    try { state.settings.uiLang = lang; } catch (e) {}
  }

  function setTab(tab) {
    state.tab = tab;
    $$('.app-tabs .tab').forEach(b => b.classList.toggle('active', b.getAttribute('data-tab') === tab));
    render();
    if (tab === 'styles') bridge.call('list_styles');
  }

  function bindTabs() {
    $$('.app-tabs .tab').forEach(btn => {
      btn.addEventListener('click', () => setTab(btn.getAttribute('data-tab')));
    });
  }


  // =====================================================================
  //  إعدادات الواجهة: الثيم / لون التمييز / شكل الأركان / حجم الخط
  // =====================================================================
  const UI_DEFAULTS = { theme: 'dark', accent: '#ff6b1a', shape: 'soft', size: 'normal', syncFtb: true };
  const THEMES = {
    dark:     { ar: 'داكن',        en: 'Dark',     sw: ['#0b0e13', '#171c25', '#2d3644'] },
    midnight: { ar: 'ليلي أزرق',   en: 'Midnight', sw: ['#080b14', '#121a2c', '#2a3858'] },
    graphite: { ar: 'جرافيت',      en: 'Graphite', sw: ['#121212', '#1f1f1f', '#3a3a3a'] },
    forest:   { ar: 'أخضر غامق',   en: 'Forest',   sw: ['#0a0f0d', '#141e19', '#2c4136'] },
    light:    { ar: 'فاتح',        en: 'Light',    sw: ['#eef1f5', '#ffffff', '#c6cedb'] }
  };
  const ACCENTS = ['#ff6b1a', '#f59e0b', '#22c55e', '#14b8a6', '#3b82f6', '#8b5cf6', '#ec4899', '#ef4444'];
  const SHAPES  = { sharp: ['حادة', 'Sharp'], soft: ['متوسطة', 'Soft'], rounded: ['دائرية', 'Rounded'] };
  const SIZES   = { small: ['صغير', 'Small', '12px'], normal: ['عادي', 'Normal', '13px'], large: ['كبير', 'Large', '14.5px'] };

  state.ui = Object.assign({}, UI_DEFAULTS);

  const hex2rgb = (hex) => {
    const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || '').trim());
    if (!m) return [255, 107, 26];
    const n = parseInt(m[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  const rgb2hex = (r, g, b) => '#' + [r, g, b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
  const mix = (hex, target, t) => {
    const [r, g, b] = hex2rgb(hex);
    return rgb2hex(r + (target - r) * t, g + (target - g) * t, b + (target - b) * t);
  };

  function applyUiPrefs(persist) {
    const ui = state.ui;
    const b = document.body, root = document.documentElement.style;
    if (ui.theme && ui.theme !== 'dark' && THEMES[ui.theme]) b.setAttribute('data-theme', ui.theme);
    else b.removeAttribute('data-theme');
    b.setAttribute('data-shape', SHAPES[ui.shape] ? ui.shape : 'soft');
    const [r, g, bl] = hex2rgb(ui.accent);
    root.setProperty('--accent', ui.accent);
    root.setProperty('--accent-2', mix(ui.accent, 255, .22));
    root.setProperty('--accent-dk', mix(ui.accent, 0, .28));
    root.setProperty('--accent-rgb', `${r},${g},${bl}`);
    root.setProperty('--ui-scale', (SIZES[ui.size] || SIZES.normal)[2]);

    // القيم المحسوبة (للشريط العائم) + حفظ
    const cs = getComputedStyle(b);
    const v = (k) => cs.getPropertyValue(k).trim();
    ui.vars = {
      bg: v('--bg'), panel: v('--panel'), card: v('--card'), border: v('--border'), border2: v('--border-2'),
      text: v('--text'), text2: v('--text-2'), text3: v('--text-3'), hdrA: v('--hdr-a'), hdrB: v('--hdr-b'),
      surf2: v('--surf-2'), strong: v('--strong'),
      accent: ui.accent, accent2: mix(ui.accent, 255, .22), accentRgb: `${r},${g},${bl}`,
      radius: ui.shape === 'sharp' ? '2px' : (ui.shape === 'rounded' ? '12px' : '6px')
    };
    state.settings.ui = ui;
    try { localStorage.setItem('cnUi', JSON.stringify(ui)); } catch (e) {}
    if (persist) {
      clearTimeout(applyUiPrefs._t);
      applyUiPrefs._t = setTimeout(() => bridge.call('save_settings', JSON.stringify(state.settings)), 350);
    }
  }

  function loadUiPrefsLocal() {
    try {
      const raw = localStorage.getItem('cnUi');
      if (raw) state.ui = Object.assign({}, UI_DEFAULTS, JSON.parse(raw));
    } catch (e) {}
    applyUiPrefs(false);
  }

  function bindSettingsButton() {
    const btn = $('#settingsBtn');
    if (btn && !btn.__cnBound) { btn.__cnBound = true; btn.addEventListener('click', (e) => { e.preventDefault(); e.stopPropagation(); openSettings(); }); }
  }

  function settingsBodyHtml() {
    const en = isEn(), ui = state.ui;
    const L = (ar, e) => en ? e : ar;
    const themeCards = Object.entries(THEMES).map(([id, t]) => `
      <button type="button" class="set-theme ${ui.theme === id ? 'active' : ''}" data-set-theme="${id}">
        <span class="set-theme-prev" style="background:${t.sw[0]};border-color:${t.sw[2]}">
          <i style="background:${t.sw[1]};border-color:${t.sw[2]}"></i>
          <i style="background:${t.sw[1]};border-color:${t.sw[2]}"></i>
          <u style="background:${ui.accent}"></u>
        </span>
        <b>${en ? t.en : t.ar}</b>
      </button>`).join('');
    const accents = ACCENTS.map(c => `
      <button type="button" class="set-swatch ${ui.accent.toLowerCase() === c ? 'active' : ''}" data-set-accent="${c}" style="background:${c}" aria-label="${c}"></button>`).join('');
    const seg = (map, key, cur) => Object.entries(map).map(([id, t]) =>
      `<button type="button" class="set-seg ${cur === id ? 'active' : ''}" data-set-${key}="${id}">${en ? t[1] : t[0]}</button>`).join('');
    return `
      <div class="form-section"><h4>${L('الثيم (ألوان الواجهة)', 'Theme')}</h4><div class="set-themes">${themeCards}</div></div>
      <div class="form-section"><h4>${L('لون التمييز', 'Accent colour')}</h4>
        <div class="set-accents">${accents}
          <label class="set-custom" title="${L('لون مخصص', 'Custom colour')}">
            <input type="color" id="setAccentCustom" value="${ui.accent}"/><span>＋</span>
          </label>
        </div>
      </div>
      <div class="form-section"><h4>${L('شكل الأركان', 'Corner style')}</h4><div class="set-segs">${seg(SHAPES, 'shape', ui.shape)}</div></div>
      <div class="form-section"><h4>${L('حجم الخط', 'Text size')}</h4><div class="set-segs">${seg(SIZES, 'size', ui.size)}</div></div>
      <label class="set-check"><input type="checkbox" id="setSyncFtb" ${ui.syncFtb !== false ? 'checked' : ''}/>
        <span>${L('تطبيق نفس الألوان على القائمة العائمة', 'Apply the same colours to the floating toolbar')}</span></label>`;
  }

  function openSettings() {
    let ov = document.getElementById('cnSettingsOverlay');
    if (!ov) {
      ov = document.createElement('div');
      ov.id = 'cnSettingsOverlay';
      ov.className = 'cn-modal-overlay';
      document.body.appendChild(ov);
      ov.addEventListener('click', (e) => { if (e.target === ov) closeSettings(); });
    }
    const en = isEn();
    ov.innerHTML = `
      <div class="cn-modal cn-settings">
        <div class="cn-modal-header">
          <h3>⚙ ${en ? 'Interface settings' : 'إعدادات الواجهة'}</h3>
          <button type="button" class="cn-modal-close" id="setClose">✕</button>
        </div>
        <div class="cn-modal-body" id="setBody">${settingsBodyHtml()}</div>
        <div class="cn-modal-footer">
          <button type="button" class="btn btn-secondary" id="setReset">${en ? 'Reset' : 'إعادة الضبط'}</button>
          <button type="button" class="btn btn-primary" id="setDone">${en ? 'Done' : 'تم'}</button>
        </div>
      </div>`;
    bindSettingsBody(ov);
    ov.classList.add('visible');
  }

  function closeSettings() {
    const ov = document.getElementById('cnSettingsOverlay');
    if (ov) ov.classList.remove('visible');
    bridge.call('save_settings', JSON.stringify(state.settings));
  }

  function refreshSettingsBody() {
    const body = $('#setBody'); if (!body) return;
    body.innerHTML = settingsBodyHtml();
    bindSettingsBody(document.getElementById('cnSettingsOverlay'));
  }

  function bindSettingsBody(ov) {
    const set = (patch) => { Object.assign(state.ui, patch); applyUiPrefs(true); refreshSettingsBody(); };
    $('#setClose', ov)?.addEventListener('click', closeSettings);
    $('#setDone', ov)?.addEventListener('click', closeSettings);
    $('#setReset', ov)?.addEventListener('click', () => set(Object.assign({}, UI_DEFAULTS)));
    $$('[data-set-theme]', ov).forEach(b => b.addEventListener('click', () => set({ theme: b.getAttribute('data-set-theme') })));
    $$('[data-set-accent]', ov).forEach(b => b.addEventListener('click', () => set({ accent: b.getAttribute('data-set-accent') })));
    $$('[data-set-shape]', ov).forEach(b => b.addEventListener('click', () => set({ shape: b.getAttribute('data-set-shape') })));
    $$('[data-set-size]', ov).forEach(b => b.addEventListener('click', () => set({ size: b.getAttribute('data-set-size') })));
    $('#setAccentCustom', ov)?.addEventListener('input', (e) => { state.ui.accent = e.target.value; applyUiPrefs(true); });
    $('#setAccentCustom', ov)?.addEventListener('change', () => refreshSettingsBody());
    $('#setSyncFtb', ov)?.addEventListener('change', (e) => { state.ui.syncFtb = !!e.target.checked; applyUiPrefs(true); });
  }

  function setNav(nav) {
    state.nav = nav || 'library';
    $$('.sidebar [data-nav]').forEach(b => b.classList.toggle('active', b.getAttribute('data-nav') === state.nav));
    if (state.tab !== 'cabinets') setTab('cabinets'); else render();
  }

  function bindSidebar() {
    // event delegation على الـ sidebar كلها: يشتغل حتى لو الأزرار اتعاد رسمها
    const side = $('.sidebar');
    if (!side || side.__cnBound) return;
    side.__cnBound = true;
    side.addEventListener('click', (ev) => {
      const btn = ev.target && ev.target.closest ? ev.target.closest('[data-nav]') : null;
      if (!btn || !side.contains(btn)) return;
      ev.preventDefault();
      const nav = btn.getAttribute('data-nav');
      if (nav === 'create')   return onCreateCabinet();
      if (nav === 'save')     return onSaveSettings();
      if (nav === 'settings') return openSettings();
      setNav(nav);
    });
  }

  function boot() {
    loadUiPrefsLocal();
    bindSettingsButton();
    bindHeader();
    bindTabs();
    bindSidebar();
    enforceDoorType();
    setLanguage('ar');
    render();
    setupTranslator();
    ensureCustomStyleModal();
    bridge.call('ui_ready');

    document.addEventListener('cn:event', e => {
      const { event, payload } = e.detail || {};
      console.log('[App] Ruby event:', event, payload);

      if (event === 'app_booted') {
        if (payload && payload.settings && Object.keys(payload.settings).length > 0) {
          Object.assign(state.settings, payload.settings);
          if (!state.settings.drawerHeights) state.settings.drawerHeights = [230, 230, 230];
          if (!state.settings.drawerCount)   state.settings.drawerCount = 3;
          if (state.settings.ovenDrawerBox === undefined) state.settings.ovenDrawerBox = true;
          if (state.settings.ovenVent === undefined) state.settings.ovenVent = false;
          if (!state.settings.cornerWRight) state.settings.cornerWRight = 900;
          if (!state.settings.cornerWLeft)  state.settings.cornerWLeft  = 900;
          if (!state.settings.cornerDRight) state.settings.cornerDRight = 580;
          if (!state.settings.cornerDLeft)  state.settings.cornerDLeft  = 580;
          if (!state.settings.fixedSide)    state.settings.fixedSide    = 'left';
          if (!state.settings.counterWidth) state.settings.counterWidth = 500;
          if (!state.settings.fillerWidth)  state.settings.fillerWidth  = 150;
          if (!state.settings.tallBottomType) state.settings.tallBottomType = 'drawers';   // ⭐ جديد
          if (!state.settings.tallBottomH) state.settings.tallBottomH = 620;
          if (!state.settings.tallOvenH)   state.settings.tallOvenH   = 600;
          if (!state.settings.tallMicroH)  state.settings.tallMicroH  = 450;
          if (!state.settings.tsLayout)    state.settings.tsLayout    = 'door';
          if (state.settings.tsHandles === undefined) state.settings.tsHandles = false;
          if (!state.settings.tsDrawerH)   state.settings.tsDrawerH   = 250;
          if (state.settings.tsDrawerN === undefined) state.settings.tsDrawerN = 0;
          if (!state.settings.tsSplitH)    state.settings.tsSplitH    = 1200;
          if (state.settings.tsShelves === undefined) state.settings.tsShelves = 4;
          if (state.settings.tsClearH === undefined)  state.settings.tsClearH  = 0;
          if (state.settings.tsShelfPos === undefined) state.settings.tsShelfPos = '';
        }
        if (state.settings.ui) { state.ui = Object.assign({}, UI_DEFAULTS, state.settings.ui); applyUiPrefs(false); }
        enforceDoorType();
        if (state.settings.uiLang && state.settings.uiLang !== state.lang) setLanguage(state.settings.uiLang);
        render();
      }

      if (event === 'cabinet_created' && payload) {
        if (payload.success) showToast('✅ تم إنشاء ' + (payload.name || 'الوحدة'));
        else showToast('❌ فشل الإنشاء', 'err');
      }

      if (event === 'settings_saved') showToast('✅ تم حفظ الإعدادات');
      if (event === 'open_settings') openSettings();

      if (event === 'styles_list') {
        state.stylesList = payload;
        if (state.tab === 'styles') {
          render();
          $$('#mainPanel [data-apply-style]').forEach(b => {
            b.disabled = false; b.textContent = 'تطبيق';
          });
        }
      }

      if (event === 'available_materials') {
        state.materialsList = payload;
        populateMaterialDropdowns();
      }

      if (event === 'style_applied') {
        const isSuccess = !!payload.success;
        $$('#mainPanel [data-apply-style]').forEach(b => {
          b.disabled = false; b.textContent = 'تطبيق';
        });
        if (isSuccess) showToast(`✅ تم تطبيق "${payload.style}" على ${payload.count} قطعة`);
        else            showToast(`❌ ${payload.reason || 'فشل التطبيق'}`, 'err');
        bridge.call('list_styles');
      }

      if (event === 'style_saved') {
        if (payload.success) { showToast('✅ تم حفظ النمط'); bridge.call('list_styles'); }
        else showToast(`❌ ${payload.reason || 'فشل الحفظ'}`, 'err');
      }

      if (event === 'style_deleted') {
        if (payload.success) { showToast('✅ تم حذف النمط'); bridge.call('list_styles'); }
      }

      if (event === 'dialog_state') {
        document.body.classList.toggle('collapsed', !!(payload && payload.collapsed));
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();