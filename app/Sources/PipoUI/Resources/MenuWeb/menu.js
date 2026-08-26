/* Canonical MenuWeb runtime: native state adapter + deterministic showcase adapter. */
(function menuRuntime() {
  'use strict';
  const params = new URLSearchParams(window.location.search);
  const mode = params.get('mode') === 'demo' ? 'demo' : 'native';
  if (params.get('embedded') === '1') document.documentElement.classList.add('embedded');
  const nativeBridge = window.pipo;
  const requests = new Map();
  const allowed = new Set(['ui.ready', 'refresh', 'refreshSection', 'selectTab', 'loadCourse', 'updateSettings', 'updateChannel', 'markSeen', 'undoSeen', 'snooze', 'openDestination', 'copyDetails', 'addToCalendar', 'requestCalendarAccess', 'pinCourse', 'unpinCourse', 'hideCourse', 'restoreCourse', 'clearCache', 'checkForUpdates', 'exportDiagnostics', 'retrySecureStorage', 'setInspectorVisible', 'dismissMenu', 'signOut']);
  let currentState = null;
  let revision = 0;
  let selectedItem = null;
  let selectedType = null;
  let activeTab = 'today';
  let inspectorTrigger = null;
  let inspectorCloseTimer = null;
  let inspectorOpenToken = 0;
  const tabState = {
    today: { query: '', courseFilter: 'all', categoryFilter: 'all' },
    courses: { query: '', courseFilter: 'all', categoryFilter: 'all' },
    settings: { query: '', courseFilter: 'all', categoryFilter: 'all' }
  };
  const sectionSignatures = new Map();
  let todayShellReady = false;
  const el = (tag, className, value) => { const node = document.createElement(tag); if (className) node.className = className; if (value != null) node.textContent = String(value); return node; };
  const meaningful = value => value != null && !['', '-', '—', 'null', 'undefined'].includes(String(value).trim().toLowerCase());
  const field = (value, fallback = '—') => meaningful(value) ? value : fallback;
  const valueFor = (object, ...keys) => keys.map(key => object?.[key]).find(value => value != null && value !== '');
  const courseIDFor = item => valueFor(item, 'courseID', 'course_id');
  const courseNameFor = item => valueFor(item, 'courseName', 'course_name');
  const itemTitle = item => field(valueFor(item, 'title', 'name', 'shortName', 'short_name', 'label'), 'LMS item');
  const itemDetail = item => valueFor(item, 'body', 'detail', 'description', 'feedback', 'excerpt', 'message');
  const formatTimestamp = value => { if (!meaningful(value)) return null; const raw = String(value); if (!/^\d{4}-\d{2}-\d{2}T/.test(raw)) return raw; const date = new Date(raw); if (Number.isNaN(date.valueOf())) return raw; const now = new Date(); const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()); const target = new Date(date.getFullYear(), date.getMonth(), date.getDate()); const days = Math.round((target - start) / 86400000); const day = days === 0 ? 'Today' : days === 1 ? 'Tomorrow' : days > 1 && days < 7 ? new Intl.DateTimeFormat(undefined, { weekday: 'short' }).format(date) : new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date); const time = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(date); return `${day} · ${time}`; };
  const dateText = item => valueFor(item, 'due', 'date') || formatTimestamp(valueFor(item, 'timestampISO', 'timestamp'));
  const itemText = item => [courseNameFor(item), valueFor(item, 'subtitle', 'courseCode', 'course_code'), dateText(item)].filter(Boolean).join(' · ');
  const courseActivities = course => {
    const courseID = String(course?.id || courseIDFor(course) || '');
    if (!courseID || !currentState) return [];
    const sections = ['nextUp', 'schedule', 'dueSoon', 'newAssignments', 'notifications', 'messages', 'gradeFeedback', 'announcements', 'resources'];
    const seen = new Set();
    return sections.flatMap(section => currentState[section] || [])
      .filter(item => String(courseIDFor(item) || '') === courseID)
      .filter(item => { const key = String(item?.entityKey || item?.id || `${itemTitle(item)}:${dateText(item) || ''}`); if (seen.has(key)) return false; seen.add(key); return true; });
  };
  const cardSecondary = (item, type) => {
    if (type !== 'course') return [type === 'activity' ? item?.sourceLabel : null, itemText(item) || itemDetail(item) || type[0].toUpperCase() + type.slice(1)].filter(Boolean).join(' · ');
    const suppliedCount = valueFor(item, 'upcomingCount', 'upcoming_count');
    const count = suppliedCount == null ? courseActivities(item).length : Number(suppliedCount);
    const publishedTotal = valueFor(item, 'publishedTotal', 'published_total');
    const metadata = [valueFor(item, 'shortName', 'short_name'), meaningful(publishedTotal) && `Grade ${publishedTotal}`, `${count} upcoming`].filter(Boolean);
    return metadata.join(' · ');
  };
  function request(action, payload = {}, source = 'main') {
    if (!allowed.has(action)) return null;
    if (action !== 'ui.ready' && action !== 'setInspectorVisible' && action !== 'dismissMenu') {
      const audio = document.getElementById('pipo-click');
      if (audio) { audio.currentTime = 0; audio.play().catch(() => {}); }
    }
    const generatedID = `web-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const outbound = { ...payload, requestID: generatedID, revision };
    const nativeID = nativeBridge?.request ? nativeBridge.request(action, outbound) : null;
    const requestID = typeof nativeID === 'string' && nativeID ? nativeID : generatedID;
    const sourcePanel = source === 'inspector' ? document.getElementById('inspector-panel') : document.getElementById('main-panel');
    requests.set(requestID, { action, payload: outbound, source: sourcePanel || source });
    const message = { action, payload: { ...outbound, requestID } };
    window.dispatchEvent(new CustomEvent('pipo:request', { detail: { requestID, ...message } }));
    if (mode === 'demo') window.setTimeout(() => resolveResponse({ requestID, success: true }), 80);
    return requestID;
  }
  function resolveResponse(response) {
    if (!response?.requestID || !requests.has(response.requestID)) return;
    const pending = requests.get(response.requestID); requests.delete(response.requestID);
    if (pending?.action === 'loadCourse' && response.data) {
      const target = String(response.targetID || pending.payload?.courseID || ''); const selected = String(selectedItem?.id || selectedItem?.courseID || ''); const inspector = document.getElementById('inspector-panel');
      const responseRevision = Number(response.revision ?? pending.payload?.revision ?? 0);
      const inspectorActive = inspector && (!inspector.classList.contains('hidden') || inspector.dataset.opening === 'true') && inspector.dataset.closing !== 'true';
      if (inspectorActive && target && target === selected && responseRevision >= revision && responseRevision >= Number(pending.payload?.revision || 0)) renderCourseDetail(response.data);
    }
    if (pending?.action === 'setInspectorVisible' && pending.payload?.visible === true) {
      const inspector = document.getElementById('inspector-panel');
      if (response.success === false) {
        if (inspector) { delete inspector.dataset.opening; delete inspector.dataset.openToken; }
      } else {
        revealInspector(Number(pending.payload?.openToken || 0));
      }
    }
    const labels = { refresh: 'Pipo refreshed', refreshSection: 'Section refreshed', markSeen: 'Marked as seen', undoSeen: 'Restored as unseen', snooze: 'Snoozed for one hour', openDestination: 'Opened in LMS', copyDetails: 'Details copied', addToCalendar: 'Added to Calendar', requestCalendarAccess: 'Calendar access updated', pinCourse: 'Course pinned', unpinCourse: 'Course unpinned', hideCourse: 'Course hidden', restoreCourse: 'Course restored', updateSettings: 'Settings saved', updateChannel: 'Update channel saved', clearCache: 'Saved dashboard cleared', checkForUpdates: 'Update check started', exportDiagnostics: 'Diagnostics exported', retrySecureStorage: 'Secure storage checked' };
    if (response.success === false) showToast(response.error || 'Action failed', pending?.source);
    else if (labels[pending?.action]) {
      // Native adapters may return function-shaped completion text. Keep UI copy human.
      showToast(labels[pending.action], pending?.source);
    }
  }
  if (!nativeBridge?.request) window.pipo = { version: 1, available: false, mode, request };
  else window.pipo = Object.freeze({ ...nativeBridge, mode, request });
  function showToast(message, source = 'main') {
    const toast = document.getElementById('toast'); const target = document.getElementById('toast-message'); if (!toast || !target) return;
    const inspector = document.getElementById('inspector-panel');
    const panel = source?.nodeType === 1 ? source : source === 'inspector' ? inspector : document.getElementById('main-panel');
    const useInspector = panel === inspector;
    if (panel && toast.parentElement !== panel) panel.append(toast);
    if (panel) { toast.style.left = '50%'; toast.style.top = 'auto'; toast.style.bottom = `${useInspector ? 48 : 62}px`; }
    target.textContent = String(message); toast.classList.remove('opacity-0', 'translate-y-4'); toast.classList.add('opacity-100', 'translate-y-0');
    window.clearTimeout(showToast.timer); showToast.timer = window.setTimeout(() => { toast.classList.add('opacity-0', 'translate-y-4'); toast.classList.remove('opacity-100', 'translate-y-0'); }, 2200);
  }
  function revealInspector(token) {
    const inspector = document.getElementById('inspector-panel');
    if (!inspector || token !== inspectorOpenToken || Number(inspector.dataset.openToken || 0) !== token || inspector.dataset.closing === 'true') return;
    window.requestAnimationFrame(() => window.requestAnimationFrame(() => {
      if (token !== inspectorOpenToken || Number(inspector.dataset.openToken || 0) !== token || inspector.dataset.closing === 'true') return;
      inspector.classList.remove('hidden', 'inspector-enter', 'inspector-exit');
      inspector.classList.add('flex');
      void inspector.offsetWidth;
      inspector.classList.add('inspector-enter');
      inspector.setAttribute('aria-hidden', 'false');
      delete inspector.dataset.opening;
      syncInspectorModality();
      document.getElementById('inspector-close')?.focus({ preventScroll: true });
    }));
  }
  function openItemInspector(type, item, skipLoad = false, trigger = null) {
    const inspector = document.getElementById('inspector-panel'); if (!inspector) return;
    window.clearTimeout(inspectorCloseTimer); inspectorCloseTimer = null; delete inspector.dataset.closing;
    if (trigger) inspectorTrigger = trigger;
    selectedItem = item; selectedType = type;
    const shouldLoadCourse = type === 'course' && mode === 'native' && !skipLoad;
    document.getElementById('inspector-category').textContent = type === 'course' ? 'Course' : type[0].toUpperCase() + type.slice(1);
    document.getElementById('inspector-title').textContent = itemTitle(item);
    document.getElementById('inspector-subtitle').textContent = itemText(item) || (type === 'course' ? 'Course details' : 'LMS activity');
    const body = document.getElementById('inspector-body');
    const detail = itemDetail(item) || (item?.detailStatus === 'redacted' ? 'Details are unavailable in the offline cache. Open this item in the LMS when connected.' : null);
    body.classList.toggle('hidden', !detail);
    body.replaceChildren(...(detail ? [el('div', 'text-neutral-200 leading-relaxed', detail)] : []));
    syncActivityDetails(type, item);
    syncInspectorCourseData(type === 'course' ? item : null);
    syncInspectorGrades(type === 'course' ? (item.grades || []) : null);
    const open = document.getElementById('inspector-open-label'); if (open) open.textContent = type === 'course' ? 'Open course in LMS' : 'Open item in LMS';
    const alreadyActive = !inspector.classList.contains('hidden') || inspector.dataset.opening === 'true';
    if (alreadyActive) {
      if (shouldLoadCourse) request('loadCourse', { courseID: item?.id });
      return;
    }
    const openToken = ++inspectorOpenToken;
    inspector.dataset.opening = 'true';
    inspector.dataset.openToken = String(openToken);
    inspector.setAttribute('aria-hidden', 'true');
    request('setInspectorVisible', { visible: true, itemID: item?.id || null, openToken });
    if (shouldLoadCourse) request('loadCourse', { courseID: item?.id });
    if (!nativeBridge?.request && mode !== 'demo') revealInspector(openToken);
  }
  function syncActivityDetails(type, item) {
    const block = document.getElementById('inspector-activity-details');
    const isActivity = type !== 'course';
    block?.classList.toggle('hidden', !isActivity);
    if (!isActivity) return;
    const values = {
      'activity-course': courseNameFor(item) || 'Course not supplied',
      'activity-instructor': valueFor(item, 'instructor') || 'Not supplied',
      'activity-kind': valueFor(item, 'kind') || type,
      'activity-due': dateText(item) || 'No date supplied'
    };
    Object.entries(values).forEach(([id, value]) => { const node = document.getElementById(id); if (node) node.textContent = value; });
  }
  function syncInspectorCourseData(course) {
    const block = document.getElementById('inspector-assignments-block');
    const list = block?.querySelector('[data-course-assignments]');
    const empty = block?.querySelector('[data-course-assignments-empty]');
    if (!block || !list || !empty) return;
    block.classList.toggle('hidden', !course);
    if (!course) return;
    const courseID = String(course?.id || courseIDFor(course) || '');
    const detailActivities = Array.isArray(course?.assignments) ? course.assignments : [];
    const assignments = detailActivities.length ? detailActivities : courseActivities({ id: courseID });
    const expected = courseActivities({ id: courseID }).length || assignments.length;
    list.replaceChildren(...assignments.map(item => itemCard(item, 'activity')));
    list.hidden = assignments.length === 0;
    empty.textContent = expected > assignments.length
      ? `${expected} upcoming ${expected === 1 ? 'activity' : 'activities'} — details unavailable.`
      : 'No upcoming activities.';
    empty.classList.toggle('hidden', assignments.length !== 0);
  }
  function syncInspectorGrades(grades) {
    const block = document.getElementById('inspector-grades-block');
    const list = block?.querySelector('[data-course-grades]');
    const empty = block?.querySelector('[data-course-grades-empty]');
    if (!block || !list || !empty) return;
    if (grades == null) { block.classList.add('hidden'); return; }
    block.classList.remove('hidden');
    const rows = (Array.isArray(grades) ? grades : []).map(grade => {
      const row = el('article', 'mac-card rounded-xl p-2.5 space-y-1.5');
      const heading = el('div', 'flex items-start justify-between gap-3');
      const title = el('span', 'text-neutral-200 font-medium min-w-0 leading-snug', itemTitle(grade));
      const publishedGrade = valueFor(grade, 'publishedGrade', 'published_grade');
      const badge = el('span', 'rounded-md bg-rose-500/15 border border-rose-500/25 px-2 py-0.5 text-rose-300 font-mono text-[11px] shrink-0', field(publishedGrade, 'Published'));
      heading.append(title, badge);
      row.append(heading);
      const feedback = valueFor(grade, 'feedback', 'excerpt');
      if (meaningful(feedback)) row.append(el('p', 'text-[10px] text-neutral-400 leading-relaxed', feedback));
      const timestamp = dateText(grade);
      if (meaningful(timestamp)) row.append(el('div', 'text-[10px] text-neutral-500', timestamp));
      return row;
    });
    list.replaceChildren(...rows);
    list.hidden = rows.length === 0;
    empty.classList.toggle('hidden', rows.length !== 0);
  }
  function renderCourseDetail(detail) {
    const course = detail?.course || selectedItem || {};
    selectedItem = { ...course, destination: detail?.destination, courseID: course.id };
    const warning = Array.isArray(detail?.failures) && detail.failures.length ? 'Some course sections are unavailable.' : '';
    openItemInspector('course', { ...selectedItem, ...course, assignments: detail?.assignments || [], grades: detail?.grades || [], detail: warning }, true);
  }
  function closeInspectorSafe() {
    const inspector = document.getElementById('inspector-panel');
    if (!inspector || inspector.classList.contains('hidden')) return false;
    if (inspector.dataset.closing === 'true') return true;
    inspectorOpenToken += 1;
    delete inspector.dataset.opening;
    delete inspector.dataset.openToken;
    inspector.dataset.closing = 'true';
    inspector.classList.remove('inspector-enter');
    inspector.classList.add('inspector-exit');
    inspector.setAttribute('aria-hidden', 'true');
    function onInspectorExitEnd(event) {
      if (event.target === inspector && event.animationName === 'inspector-panel-out') finishClose();
    }
    const finishClose = () => {
      if (inspector.dataset.closing !== 'true') return;
      window.clearTimeout(inspectorCloseTimer); inspectorCloseTimer = null;
      inspector.removeEventListener('animationend', onInspectorExitEnd);
      inspector.classList.add('hidden');
      inspector.classList.remove('flex', 'inspector-exit');
      delete inspector.dataset.closing;
      const main = document.getElementById('main-panel');
      main?.removeAttribute('inert'); main?.removeAttribute('aria-hidden');
      inspectorTrigger?.focus?.({ preventScroll: true }); inspectorTrigger = null;
      request('setInspectorVisible', { visible: false });
    };
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) finishClose();
    else {
      inspector.addEventListener('animationend', onInspectorExitEnd);
      inspectorCloseTimer = window.setTimeout(finishClose, 240);
    }
    return true;
  }
  function syncInspectorModality() { const inspector = document.getElementById('inspector-panel'); const main = document.getElementById('main-panel'); const compactOpen = window.matchMedia('(max-width: 735px)').matches && inspector && !inspector.classList.contains('hidden'); if (compactOpen) { main?.setAttribute('inert', ''); main?.setAttribute('aria-hidden', 'true'); } else { main?.removeAttribute('inert'); main?.removeAttribute('aria-hidden'); } }
  function itemCard(item, type) {
    const card = el('article', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300 cursor-pointer'); card.tabIndex = 0; card.setAttribute('role', 'button'); card.setAttribute('aria-label', `${itemTitle(item)}. ${cardSecondary(item, type)}`); card.dataset.itemId = item?.id || ''; card.dataset.entityKey = item?.entityKey || item?.id || '';
    card.dataset.course = String(courseIDFor(item) || courseNameFor(item) || item?.id || '').toLowerCase(); card.dataset.category = type;
    const secondary = cardSecondary(item, type);
    card.append(el('div', 'item-title font-medium text-neutral-200 leading-snug', itemTitle(item)));
    if (secondary) card.append(el('div', 'item-secondary text-[10px] text-neutral-400 mt-0.5 leading-snug', secondary));
    card.addEventListener('click', () => openItemInspector(type, item, false, card));
    card.addEventListener('contextmenu', event => { event.preventDefault(); selectedItem = item; selectedType = type; showContextMenu(event.clientX, event.clientY); });
    card.addEventListener('keydown', event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); openItemInspector(type, item, false, card); } }); return card;
  }
  function showContextMenu(x, y) {
    const menu = document.getElementById('item-context-menu'); if (!menu) return;
    const buttons = [...menu.querySelectorAll('button')];
    const courseID = String(selectedItem?.id || selectedItem?.courseID || '');
    if (selectedType === 'course') {
      const pinned = currentState?.localState?.pinnedCourseIDs?.includes(courseID);
      const labels = ['Open LMS', 'Copy details', pinned ? 'Unpin course' : 'Pin course', 'Hide course'];
      buttons.forEach((button, index) => { button.hidden = index >= labels.length; if (labels[index]) button.querySelector('span').textContent = labels[index]; });
    } else {
      const labels = ['Open LMS', 'Copy details', 'Mark as seen', 'Snooze reminder', 'Add to Calendar'];
      buttons.forEach((button, index) => { button.hidden = false; button.querySelector('span').textContent = labels[index]; });
    }
    buttons.forEach(button => { const label = button.textContent.trim().toLowerCase(); button.dataset.action = label.includes('unpin') ? 'unpinCourse' : label.includes('pin') ? 'pinCourse' : label.includes('hide') ? 'hideCourse' : label.includes('copy') ? 'copyDetails' : label.includes('seen') ? 'markSeen' : label.includes('snooze') ? 'snooze' : label.includes('calendar') ? 'addToCalendar' : 'openDestination'; });
    menu.style.left = `${Math.min(x, window.innerWidth - 200)}px`; menu.style.top = `${Math.min(y, window.innerHeight - 190)}px`; menu.classList.remove('hidden');
  }
  function section(title, key, items, type, status = 'ready', collapsed = false) {
    const wrap = el('section', 'space-y-1.5'); const heading = el('button', 'w-full flex items-center justify-between py-0.5 text-rose-400 font-semibold text-xs'); heading.type = 'button'; heading.setAttribute('aria-expanded', 'true');
    wrap.dataset.sectionKey = key;
    const headingLabel = el('span', 'flex items-center gap-2', title); const headingIcon = el('i', 'fa-solid fa-chevron-up text-[10px] text-neutral-500 group-hover:text-neutral-300 transition-transform'); heading.append(headingLabel, headingIcon);
    const content = el('div', 'space-y-1.5'); content.dataset.sectionContent = key;
    if (items?.length) items.forEach(item => content.append(itemCard(item, type)));
    else if (status === 'loading') content.append(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-400 animate-pulse', `Loading ${title.toLowerCase()}…`));
    else content.append(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-400', `No ${title.toLowerCase()}`));
    heading.id = `section-${key}-toggle`; content.id = `section-${key}-content`; heading.setAttribute('aria-controls', content.id);
    heading.addEventListener('click', () => { const collapsed = content.hidden = !content.hidden; heading.setAttribute('aria-expanded', String(!collapsed)); headingIcon.classList.toggle('fa-chevron-up', !collapsed); headingIcon.classList.toggle('fa-chevron-down', collapsed); }); wrap.append(heading, content); return wrap;
  }
  function uniqueItems(items) {
    const seen = new Set();
    return (items || []).filter(item => { const id = String(item?.entityKey || item?.id || `${itemTitle(item)}:${dateText(item) || ''}`); if (seen.has(id)) return false; seen.add(id); return true; });
  }
  function reconcileCards(container, items, type, status = 'ready') {
    const focusedKey = document.activeElement?.dataset?.entityKey;
    const existing = new Map([...container.querySelectorAll('[data-entity-key]')].map(node => [node.dataset.entityKey, node]));
    const nodes = items.map(item => { const id = String(item?.entityKey || item?.id || ''); const signature = JSON.stringify(item); const current = existing.get(id); if (current?.dataset.signature === signature) { existing.delete(id); return current; } const card = itemCard(item, type); card.dataset.signature = signature; return card; });
    if (!nodes.length) nodes.push(el('div', 'mac-card rounded-xl p-3 text-xs text-neutral-400', status === 'loading' ? 'Loading courses…' : 'No courses available'));
    container.replaceChildren(...nodes);
    if (focusedKey) container.querySelector(`[data-entity-key="${CSS.escape(focusedKey)}"]`)?.focus({ preventScroll: true });
  }
  function renderState(state) {
    const today = document.getElementById('view-today'); const courses = document.getElementById('view-courses');
    if (today && !todayShellReady) { const greeting = el('h2', 'text-sm font-bold text-white tracking-tight'); greeting.id = 'today-greeting'; const notices = el('div', 'space-y-2'); notices.id = 'today-notices'; const sections = el('div', 'space-y-3'); sections.id = 'today-sections'; today.replaceChildren(greeting, notices, sections); todayShellReady = true; }
    const greeting = document.getElementById('today-greeting'); if (greeting) greeting.textContent = `Hello${state.studentName ? `, ${state.studentName}` : ''}`;
    const notices = document.getElementById('today-notices'); if (notices) { const nodes = []; if (state.phase === 'failed') nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-rose-400', state.errorMessage || 'Pipo could not load your LMS.')); else if (state.phase === 'offline') nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300', 'Showing saved LMS data. Some private details require a live connection.')); else if (state.phase === 'loading' || state.phase === 'authenticating') nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300 animate-pulse', 'Connecting to your LMS…')); if (state.failures?.length) nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300', 'Some LMS sections could not refresh.')); notices.replaceChildren(...nodes); }
    const consumed = new Set(); const consume = items => uniqueItems(items).filter(item => { const key = String(item?.entityKey || item?.id || ''); if (key && consumed.has(key)) return false; if (key) consumed.add(key); return true; });
    const definitions = [
      ['Up next', 'nextUp', consume(state.nextUp || []), 'activity'], ['Due soon', 'dueSoon', consume(state.dueSoon || []), 'assignment'],
      ['Schedule', 'schedule', consume(state.schedule || []), 'activity'], ['New assignments', 'newAssignments', consume(state.newAssignments || []), 'assignment'],
      ['Notifications', 'notifications', consume(state.notifications || []), 'notification'],
      ['Messages', 'messages', consume(state.messages || []), 'message'], ['Grade feedback', 'gradeFeedback', consume(state.gradeFeedback || []), 'grade'],
      ['Announcements', 'announcements', consume(state.announcements || []), 'announcement'], ['Resources', 'resources', consume(state.resources || []), 'resource']
    ];
    const sectionsRoot = document.getElementById('today-sections');
    definitions.forEach(([title, key, items, type]) => { const status = state.sectionStatuses?.[key]?.status || 'ready'; const existing = sectionsRoot?.querySelector(`[data-section-key="${key}"]`); const original = state[key] || []; if (status === 'unsupported' || (original.length > 0 && items.length === 0)) { existing?.remove(); sectionSignatures.delete(key); return; } const signature = JSON.stringify([items, status]); if (sectionSignatures.get(key) === signature && existing) return; const collapsed = existing?.querySelector('button')?.getAttribute('aria-expanded') === 'false'; const replacement = section(title, key, items, type, status, collapsed); if (collapsed) { const content = replacement.querySelector('[data-section-content]'); const button = replacement.querySelector('button'); const icon = button?.querySelector('.fa-chevron-up'); if (content) content.hidden = true; button?.setAttribute('aria-expanded', 'false'); icon?.classList.remove('fa-chevron-up'); icon?.classList.add('fa-chevron-down'); } existing ? existing.replaceWith(replacement) : sectionsRoot?.append(replacement); sectionSignatures.set(key, signature); });
    if (courses) reconcileCards(courses, state.courses || [], 'course', state.sectionStatuses?.courses?.status || 'ready');
    const phase = state.phase || 'ready';
    document.documentElement.dataset.phase = phase;
    document.documentElement.dataset.hostMode = state.hostMode || (mode === 'demo' ? 'showcase' : 'menuBar');
    const statusText = phase === 'offline' ? 'Offline cache' : phase === 'loading' || phase === 'authenticating' ? 'Connecting' : phase === 'failed' ? 'Sync failed' : state.failures?.length ? 'Partial sync' : 'Ready';
    const sync = document.getElementById('sync-status'); if (sync) sync.textContent = statusText;
    const syncDot = document.getElementById('sync-dot'); if (syncDot) syncDot.dataset.phase = phase === 'ready' && state.failures?.length ? 'offline' : phase;
    const syncButton = document.getElementById('sync-button'); if (syncButton) { syncButton.setAttribute('aria-label', `${statusText}. Refresh Pipo`); syncButton.setAttribute('aria-busy', String(phase === 'loading' || phase === 'authenticating')); }
    syncSettings(state); syncCourseFilters(state); syncLocalCourses(state); applyFilters();
  }
  function syncLocalCourses(state) {
    const container = document.getElementById('settings-courses-state'); if (!container) return;
    const pinned = state.localState?.pinnedCourseIDs || []; const hidden = state.localState?.hiddenCourseIDs || [];
    if (!pinned.length && !hidden.length) { container.textContent = 'No pinned or hidden courses'; return; }
    const buttons = [];
    pinned.forEach(courseID => { const button = el('button', 'w-full text-left px-2 py-1 rounded-lg hover:bg-white/10 text-neutral-200', `Unpin course ${courseID}`); button.dataset.action = 'unpinCourse'; button.dataset.courseId = courseID; buttons.push(button); });
    hidden.forEach(courseID => { const button = el('button', 'w-full text-left px-2 py-1 rounded-lg hover:bg-white/10 text-neutral-200', `Restore course ${courseID}`); button.dataset.action = 'restoreCourse'; button.dataset.courseId = courseID; buttons.push(button); });
    container.replaceChildren(...buttons);
  }
  function syncCourseFilters(state) {
    const current = document.querySelector('.course-filter-btn')?.parentElement; if (!current) return;
    const all = el('button', 'course-filter-btn w-full text-left px-2 py-1.5 rounded-lg hover:bg-white/10 text-neutral-200 text-[11px] truncate', 'All Courses'); all.dataset.courseFilter = 'all';
    const buttons = [all, ...(state.courses || []).map(course => { const button = el('button', 'course-filter-btn w-full text-left px-2 py-1.5 rounded-lg hover:bg-white/10 text-neutral-300 text-[11px] truncate', valueFor(course, 'shortName', 'short_name', 'name')); button.dataset.courseFilter = String(course.id).toLowerCase(); return button; })];
    current.replaceChildren(...buttons); buttons.forEach(button => button.addEventListener('click', () => { tabState[activeTab].courseFilter = button.dataset.courseFilter; applyFilters(); dismissFilter(); }));
  }
  function syncSettings(state) {
    const names = ['notificationsEnabled', 'reminderDayBefore', 'reminderHourBefore', 'assignmentNotifications', 'announcementNotifications', 'messageNotifications', 'gradeNotifications'];
    document.querySelectorAll('input.apple-switch').forEach((input, index) => { const name = names[index]; input.dataset.setting = name; if (state.settings && name in state.settings) input.checked = Boolean(state.settings[name]); });
    const refresh = document.querySelector('#view-settings input[type="range"]'); if (refresh && state.settings?.refreshMinutes) refresh.value = String(state.settings.refreshMinutes);
    const channel = document.querySelector('#view-settings select'); if (channel && state.updateChannel) channel.value = state.updateChannel;
  }
  function applyState(state) { if (!state || typeof state !== 'object' || (Number.isFinite(state.revision) && state.revision <= revision)) return; currentState = state; revision = Number.isFinite(state.revision) ? state.revision : revision + 1; renderState(state); switchTab(state.selectedTab || 'today', false); window.dispatchEvent(new CustomEvent('pipo:stateApplied', { detail: state })); }
  async function loadDemoFixture() { try { const response = await fetch('./demo-fixture.json', { cache: 'no-store' }); if (!response.ok) throw new Error(`fixture ${response.status}`); applyState(await response.json()); } catch (error) { showToast('Demo data unavailable'); window.dispatchEvent(new CustomEvent('pipo:error', { detail: error })); } }
  function applyFilters() { const state = tabState[activeTab]; const query = String(state.query || '').trim().toLowerCase(); document.querySelectorAll('#view-today [data-item-id], #view-courses [data-item-id]').forEach(card => { const belongsToActivePanel = Boolean(card.closest(`#view-${activeTab}`)); if (!belongsToActivePanel) return; const searchMatch = !query || card.textContent.toLowerCase().includes(query); const courseMatch = state.courseFilter === 'all' || card.dataset.course === state.courseFilter; const categoryMatch = activeTab !== 'today' || state.categoryFilter === 'all' || card.dataset.category === state.categoryFilter; card.hidden = !(searchMatch && courseMatch && categoryMatch); }); }
  function filterCards(query) { const value = String(query || ''); tabState[activeTab].query = value; const input = document.getElementById('search-input'); if (input && input.value !== value) input.value = value; applyFilters(); }
  function switchTab(tab, notify = true, focusTab = false) {
    const valid = ['today', 'courses', 'settings'].includes(tab) ? tab : 'today';
    const input = document.getElementById('search-input');
    if (input && activeTab !== 'settings') tabState[activeTab].query = input.value;
    activeTab = valid;
    ['today', 'courses', 'settings'].forEach(name => {
      const selected = name === valid; const panel = document.getElementById(`view-${name}`); const button = document.getElementById(`tab-${name}`);
      panel?.classList.toggle('hidden', !selected); panel?.setAttribute('aria-hidden', String(!selected));
      button?.classList.toggle('active', selected); button?.setAttribute('aria-selected', String(selected)); button?.setAttribute('tabindex', selected ? '0' : '-1');
      if (selected) button?.setAttribute('aria-current', 'page'); else button?.removeAttribute('aria-current');
    });
    const title = document.getElementById('header-title'); if (title) title.textContent = valid[0].toUpperCase() + valid.slice(1);
    document.getElementById('search-section')?.classList.toggle('hidden', valid === 'settings');
    document.getElementById('category-filters')?.classList.toggle('hidden', valid !== 'today');
    if (input) { input.value = tabState[valid].query; input.placeholder = valid === 'courses' ? 'Search courses' : 'Search today'; document.getElementById('clear-search')?.classList.toggle('hidden', !input.value); }
    dismissFilter(); applyFilters();
    if (focusTab) document.getElementById(`tab-${valid}`)?.focus();
    if (notify) request('selectTab', { tab: valid });
  }
  function dismissMenu() { const menu = document.getElementById('item-context-menu'); if (!menu || menu.classList.contains('hidden')) return false; menu.classList.add('hidden'); return true; }
  function dismissFilter() { const popover = document.getElementById('filter-popover'); if (!popover || popover.classList.contains('hidden')) return false; popover.classList.add('hidden'); document.getElementById('filter-toggle')?.setAttribute('aria-expanded', 'false'); return true; }
  function bindActions() {
    const tabNames = ['today', 'courses', 'settings'];
    tabNames.forEach((tab, index) => { const node = document.getElementById(`tab-${tab}`); if (!node) return; node.addEventListener('click', () => switchTab(tab)); node.addEventListener('keydown', event => { let next = null; if (event.key === 'ArrowRight') next = (index + 1) % tabNames.length; if (event.key === 'ArrowLeft') next = (index - 1 + tabNames.length) % tabNames.length; if (event.key === 'Home') next = 0; if (event.key === 'End') next = tabNames.length - 1; if (next == null) return; event.preventDefault(); switchTab(tabNames[next], true, true); }); });
    document.querySelectorAll('button').forEach(node => {
      const label = node.textContent.trim().toLowerCase(); let action = null;
      if (label === 'sign out') action = 'signOut'; else if (label.includes('allow calendar')) action = 'requestCalendarAccess'; else if (label.includes('refresh')) action = 'refresh'; else if (label.includes('calendar')) action = 'addToCalendar'; else if (label.includes('copy')) action = 'copyDetails'; else if (label.includes('seen')) action = 'markSeen'; else if (label.includes('snooze')) action = 'snooze'; else if (label.includes('open')) action = 'openDestination'; else if (label.includes('clear')) action = 'clearCache'; else if (label.includes('update')) action = 'checkForUpdates'; else if (label.includes('diagnostic')) action = 'exportDiagnostics';
      if (label.includes('open lms in browser')) node.dataset.lmsRoot = 'true';
      if (action) node.dataset.action = action;
    });
    document.querySelectorAll('[id^="section-"] > button, [data-collapse-target]').forEach(heading => {
      const content = heading.nextElementSibling; if (!content) return; const icon = heading.querySelector('.fa-chevron-up, .fa-chevron-down'); if (content.id) heading.setAttribute('aria-controls', content.id); heading.setAttribute('aria-expanded', 'true'); heading.addEventListener('click', () => { const collapsed = content.hidden = !content.hidden; heading.setAttribute('aria-expanded', String(!collapsed)); icon?.classList.toggle('fa-chevron-up', !collapsed); icon?.classList.toggle('fa-chevron-down', collapsed); });
    });
    document.getElementById('search-input')?.addEventListener('input', event => { tabState[activeTab].query = event.target.value; applyFilters(); document.getElementById('clear-search')?.classList.toggle('hidden', !event.target.value); });
    document.getElementById('clear-search')?.addEventListener('click', () => filterCards(''));
    document.getElementById('filter-toggle')?.addEventListener('click', event => { const popover = document.getElementById('filter-popover'); const hidden = popover?.classList.toggle('hidden'); event.currentTarget.setAttribute('aria-expanded', String(!hidden)); });
    document.querySelectorAll('.cat-filter-btn').forEach(button => button.addEventListener('click', () => { const label = button.textContent.trim().toLowerCase(); tabState[activeTab].categoryFilter = label.startsWith('all') ? 'all' : label.replace(/s$/, ''); applyFilters(); dismissFilter(); }));
    const settingNames = ['notificationsEnabled', 'reminderDayBefore', 'reminderHourBefore', 'assignmentNotifications', 'announcementNotifications', 'messageNotifications', 'gradeNotifications'];
    document.querySelectorAll('input.apple-switch').forEach((input, index) => { input.dataset.setting = input.dataset.setting || settingNames[index] || 'notificationsEnabled'; input.addEventListener('change', () => request('updateSettings', { [input.dataset.setting]: input.checked })); });
    document.querySelector('#view-settings input[type="range"]')?.addEventListener('change', event => request('updateSettings', { refreshMinutes: Number(event.target.value) }));
    document.querySelectorAll('select').forEach(select => select.addEventListener('change', () => request('updateChannel', { channel: select.value })));
    document.getElementById('inspector-back')?.addEventListener('click', closeInspectorSafe); document.getElementById('inspector-close')?.addEventListener('click', closeInspectorSafe);
    document.addEventListener('click', event => { const menu = document.getElementById('item-context-menu'); if (!event.target.closest('#item-context-menu')) dismissMenu(); if (!event.target.closest('#filter-popover') && !event.target.closest('#filter-toggle')) dismissFilter(); const actionButton = event.target.closest('[data-action]'); if (!actionButton) return; const rawAction = actionButton.dataset.action; if (rawAction.startsWith('selectTab:')) return; if (rawAction === 'closeInspector') return closeInspectorSafe(); if (rawAction === 'clearCache' && !window.confirm('Clear the saved dashboard? Pipo will fetch it again on refresh.')) return; const itemID = selectedType === 'course' ? null : selectedItem?.id; const courseID = actionButton.dataset.courseId || (selectedType === 'course' ? (selectedItem?.id || selectedItem?.courseID) : null); const payload = actionButton.dataset.lmsRoot === 'true' ? { lmsRoot: true } : courseID ? { courseID } : itemID ? { itemID } : {}; const source = actionButton.closest('#inspector-panel') ? 'inspector' : 'main'; request(rawAction, payload, source); dismissMenu(); event.preventDefault(); event.stopImmediatePropagation(); }, true);
    document.addEventListener('keydown', event => {
      if (event.key === 'Escape') { event.preventDefault(); if (dismissMenu()) return; if (dismissFilter()) { document.getElementById('filter-toggle')?.focus(); return; } if (closeInspectorSafe()) return; request('dismissMenu'); return; }
      const inspector = document.getElementById('inspector-panel');
      if (event.key !== 'Tab' || !window.matchMedia('(max-width: 735px)').matches || !inspector || inspector.classList.contains('hidden')) return;
      const focusable = [...inspector.querySelectorAll('button:not([hidden]):not([disabled]), input:not([disabled]), select:not([disabled]), [tabindex="0"]')].filter(node => node.offsetParent !== null);
      if (!focusable.length) return; const first = focusable[0]; const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); } else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    });
    window.addEventListener('resize', syncInspectorModality);
  }
  window.pipoMenu = Object.freeze({ applyState, filterCards, request, switchTab, mode });
  window.addEventListener('message', event => { if (event.data?.type === 'pipo:state') applyState(event.data.state); if (event.data?.type === 'pipo:response') resolveResponse(event.data); });
  window.addEventListener('pipo-response', event => resolveResponse(event.detail));
  window.addEventListener('pipo-state', event => applyState(event.detail));
  window.addEventListener('DOMContentLoaded', () => { bindActions(); request('ui.ready'); if (mode === 'demo') loadDemoFixture(); }, { once: true });
})();
