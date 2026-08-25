/* Canonical MenuWeb runtime: native state adapter + deterministic showcase adapter. */
(function menuRuntime() {
  'use strict';
  const params = new URLSearchParams(window.location.search);
  const mode = params.get('mode') === 'demo' ? 'demo' : 'native';
  if (params.get('embedded') === '1') document.documentElement.classList.add('embedded');
  const nativeBridge = window.pipo;
  const requests = new Map();
  const allowed = new Set(['ui.ready', 'refresh', 'refreshSection', 'selectTab', 'loadCourse', 'updateSettings', 'updateChannel', 'markSeen', 'undoSeen', 'snooze', 'openDestination', 'copyDetails', 'addToCalendar', 'requestCalendarAccess', 'pinCourse', 'unpinCourse', 'hideCourse', 'restoreCourse', 'clearCache', 'checkForUpdates', 'exportDiagnostics', 'retrySecureStorage', 'setInspectorVisible', 'signOut']);
  let currentState = null;
  let revision = 0;
  let selectedItem = null;
  let selectedType = null;
  let courseFilter = 'all';
  let categoryFilter = 'all';
  const el = (tag, className, value) => { const node = document.createElement(tag); if (className) node.className = className; if (value != null) node.textContent = String(value); return node; };
  const meaningful = value => value != null && !['', '-', '—', 'null', 'undefined'].includes(String(value).trim().toLowerCase());
  const field = (value, fallback = '—') => meaningful(value) ? value : fallback;
  const valueFor = (object, ...keys) => keys.map(key => object?.[key]).find(value => value != null && value !== '');
  const courseIDFor = item => valueFor(item, 'courseID', 'course_id');
  const courseNameFor = item => valueFor(item, 'courseName', 'course_name');
  const itemTitle = item => field(valueFor(item, 'title', 'name', 'shortName', 'short_name', 'label'), 'LMS item');
  const itemDetail = item => valueFor(item, 'body', 'detail', 'description', 'feedback', 'excerpt', 'message');
  const dateText = item => valueFor(item, 'due', 'date', 'timestamp');
  const itemText = item => [courseNameFor(item), valueFor(item, 'subtitle', 'courseCode', 'course_code'), dateText(item)].filter(Boolean).join(' · ');
  const courseAssignments = course => {
    const courseID = String(course?.id || courseIDFor(course) || '');
    if (!courseID || !currentState) return [];
    return [...(currentState.dueSoon || []), ...(currentState.newAssignments || [])]
      .filter(item => String(courseIDFor(item) || '') === courseID);
  };
  const cardSecondary = (item, type) => {
    if (type !== 'course') return itemText(item) || itemDetail(item) || type[0].toUpperCase() + type.slice(1);
    const count = Number(valueFor(item, 'upcomingCount', 'upcoming_count')) || courseAssignments(item).length;
    const publishedTotal = valueFor(item, 'publishedTotal', 'published_total');
    const metadata = [valueFor(item, 'shortName', 'short_name'), meaningful(publishedTotal) && `Grade ${publishedTotal}`, `${count} upcoming`].filter(Boolean);
    return metadata.join(' · ');
  };
  function request(action, payload = {}, source = 'main') {
    if (!allowed.has(action)) return null;
    if (action !== 'ui.ready' && action !== 'setInspectorVisible') {
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
    if (pending?.action === 'loadCourse' && response.data) renderCourseDetail(response.data);
    const labels = { refresh: 'Pipo refreshed', refreshSection: 'Section refreshed', markSeen: 'Marked as seen', undoSeen: 'Restored as unseen', snooze: 'Snoozed for one hour', openDestination: 'Opened in LMS', copyDetails: 'Details copied', addToCalendar: 'Added to Calendar', requestCalendarAccess: 'Calendar access updated', pinCourse: 'Course pinned', unpinCourse: 'Course unpinned', hideCourse: 'Course hidden', restoreCourse: 'Course restored', updateSettings: 'Settings saved', updateChannel: 'Update channel saved', clearCache: 'Saved dashboard cleared', checkForUpdates: 'Update check started', exportDiagnostics: 'Diagnostics exported', retrySecureStorage: 'Secure storage checked' };
    if (response.success === false) showToast(response.error || 'Action failed', pending?.source);
    else if (labels[pending?.action]) {
      const message = String(response.message || '').trim();
      const action = String(pending.action || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const rawCompletion = new RegExp(`^${action}\\s+(?:complete|completed|success|successful)$`, 'i');
      showToast(message && !rawCompletion.test(message) ? message : labels[pending.action], pending?.source);
    }
  }
  if (!nativeBridge?.request) window.pipo = { version: 1, available: false, mode, request };
  else window.pipo = Object.freeze({ ...nativeBridge, mode, request });
  function showToast(message, source = 'main') {
    const toast = document.getElementById('toast'); const target = document.getElementById('toast-message'); if (!toast || !target) return;
    const inspector = document.getElementById('inspector-panel'); const shell = document.getElementById('pipo-shell');
    const panel = source?.nodeType === 1 ? source : source === 'inspector' ? inspector : document.getElementById('main-panel');
    const useInspector = panel === inspector;
    if (shell && toast.parentElement !== shell) shell.append(toast);
    if (panel) { toast.style.left = `${panel.offsetLeft + panel.offsetWidth / 2}px`; toast.style.top = `${panel.offsetTop + panel.offsetHeight - (useInspector ? 48 : 62)}px`; toast.style.bottom = 'auto'; }
    target.textContent = String(message); toast.classList.remove('opacity-0', 'translate-y-4'); toast.classList.add('opacity-100', 'translate-y-0');
    window.clearTimeout(showToast.timer); showToast.timer = window.setTimeout(() => { toast.classList.add('opacity-0', 'translate-y-4'); toast.classList.remove('opacity-100', 'translate-y-0'); }, 2200);
  }
  function openItemInspector(type, item, skipLoad = false) {
    const inspector = document.getElementById('inspector-panel'); if (!inspector) return;
    selectedItem = item; selectedType = type;
    if (type === 'course' && mode === 'native' && !skipLoad) { request('loadCourse', { courseID: item?.id }); }
    document.getElementById('inspector-category').textContent = type === 'course' ? 'Course' : type[0].toUpperCase() + type.slice(1);
    document.getElementById('inspector-title').textContent = itemTitle(item);
    document.getElementById('inspector-subtitle').textContent = itemText(item) || (type === 'course' ? 'Course details' : 'LMS activity');
    const body = document.getElementById('inspector-body');
    const detail = itemDetail(item);
    body.classList.toggle('hidden', !detail);
    body.replaceChildren(...(detail ? [el('div', 'text-neutral-200 leading-relaxed', detail)] : []));
    syncActivityDetails(type, item);
    syncInspectorCourseData(type === 'course' ? item : null);
    syncInspectorGrades(type === 'course' ? (item.grades || []) : null);
    const open = document.getElementById('inspector-open-label'); if (open) open.textContent = type === 'course' ? 'Open course in LMS' : 'Open item in LMS';
    inspector.classList.remove('hidden', 'inspector-exit'); inspector.classList.add('flex', 'inspector-enter'); request('setInspectorVisible', { visible: true, itemID: item?.id || null });
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
    const assignments = Array.isArray(course?.assignments) ? course.assignments : courseAssignments({ id: courseID });
    list.replaceChildren(...assignments.map(item => itemCard(item, 'assignment')));
    list.hidden = assignments.length === 0;
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
  function closeInspectorSafe() { const inspector = document.getElementById('inspector-panel'); if (!inspector || inspector.classList.contains('hidden')) return; inspector.classList.add('hidden'); inspector.classList.remove('flex', 'inspector-enter'); request('setInspectorVisible', { visible: false }); }
  function itemCard(item, type) {
    const card = el('article', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300 cursor-pointer'); card.tabIndex = 0; card.dataset.itemId = item?.id || '';
    card.dataset.course = String(courseIDFor(item) || courseNameFor(item) || item?.id || '').toLowerCase(); card.dataset.category = type;
    const secondary = cardSecondary(item, type);
    card.append(el('div', 'font-medium text-neutral-200 truncate', itemTitle(item)));
    if (secondary) card.append(el('div', 'text-[10px] text-neutral-400 truncate mt-0.5', secondary));
    card.addEventListener('click', () => openItemInspector(type, item));
    card.addEventListener('contextmenu', event => { event.preventDefault(); selectedItem = item; selectedType = type; showContextMenu(event.clientX, event.clientY); });
    card.addEventListener('keydown', event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); openItemInspector(type, item); } }); return card;
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
  function section(title, key, items, type) {
    const wrap = el('section', 'space-y-1.5'); const heading = el('button', 'w-full flex items-center justify-between py-0.5 text-rose-400 font-semibold text-xs', title); heading.type = 'button'; heading.setAttribute('aria-expanded', 'true');
    const content = el('div', 'space-y-1.5'); content.dataset.sectionContent = key;
    if (items?.length) items.forEach(item => content.append(itemCard(item, type)));
    else content.append(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-400', `No ${title.toLowerCase()}`));
    heading.addEventListener('click', () => { const collapsed = content.hidden = !content.hidden; heading.setAttribute('aria-expanded', String(!collapsed)); }); wrap.append(heading, content); return wrap;
  }
  function uniqueItems(items) {
    const seen = new Set();
    return (items || []).filter(item => { const id = String(item?.id || `${itemTitle(item)}:${dateText(item) || ''}`); if (seen.has(id)) return false; seen.add(id); return true; });
  }
  function renderState(state) {
    const today = document.getElementById('view-today'); const courses = document.getElementById('view-courses');
    if (today) {
      const greeting = el('h2', 'text-sm font-bold text-white tracking-tight', `Hello${state.studentName ? `, ${state.studentName}` : ''}`);
      const nodes = [greeting];
      if (state.phase === 'failed') nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-rose-400', state.errorMessage || 'Pipo could not load your LMS.'));
      else if (state.phase === 'offline') nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300', 'Showing the latest saved dashboard.'));
      else if (state.phase === 'loading' || state.phase === 'authenticating') nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300 animate-pulse', 'Connecting to your LMS…'));
      if (state.failures?.length) nodes.push(el('div', 'mac-card rounded-xl p-2.5 text-xs text-neutral-300', 'Some LMS sections could not refresh.'));
      nodes.push(section('Up next', 'nextUp', state.nextUp, 'activity'));
      if (state.supported?.schedule !== false) nodes.push(section('Schedule', 'schedule', state.schedule, 'activity'));
      if (state.supported?.due_soon !== false) nodes.push(section('Due soon', 'dueSoon', uniqueItems([...(state.dueSoon || []), ...(state.newAssignments || [])]), 'assignment'));
      if (state.supported?.notifications !== false) nodes.push(section('Notifications', 'notifications', state.notifications, 'notification'));
      if (state.supported?.messages !== false) nodes.push(section('Messages', 'messages', state.messages, 'message'));
      if (state.supported?.grades !== false) nodes.push(section('Grade feedback', 'gradeFeedback', state.gradeFeedback, 'grade'));
      if (state.supported?.announcements !== false) nodes.push(section('Announcements', 'announcements', state.announcements, 'announcement'));
      if (state.supported?.resources !== false) nodes.push(section('Resources', 'resources', state.resources, 'resource'));
      today.replaceChildren(...nodes);
    }
    if (courses) { const cards = (state.courses || []).map(course => itemCard(course, 'course')); courses.replaceChildren(...(cards.length ? cards : [el('div', 'mac-card rounded-xl p-3 text-xs text-neutral-400', 'No courses available') ])); }
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
    current.replaceChildren(...buttons); buttons.forEach(button => button.addEventListener('click', () => { courseFilter = button.dataset.courseFilter; applyFilters(); document.getElementById('filter-popover')?.classList.add('hidden'); }));
  }
  function syncSettings(state) {
    const names = ['notificationsEnabled', 'reminderDayBefore', 'reminderHourBefore', 'assignmentNotifications', 'announcementNotifications', 'messageNotifications', 'gradeNotifications'];
    document.querySelectorAll('input.apple-switch').forEach((input, index) => { const name = names[index]; input.dataset.setting = name; if (state.settings && name in state.settings) input.checked = Boolean(state.settings[name]); });
    const refresh = document.querySelector('#view-settings input[type="range"]'); if (refresh && state.settings?.refreshMinutes) refresh.value = String(state.settings.refreshMinutes);
    const channel = document.querySelector('#view-settings select'); if (channel && state.updateChannel) channel.value = state.updateChannel;
  }
  function applyState(state) { if (!state || typeof state !== 'object' || (Number.isFinite(state.revision) && state.revision < revision)) return; currentState = state; revision = Number.isFinite(state.revision) ? state.revision : revision + 1; renderState(state); switchTab(state.selectedTab || 'today', false); window.dispatchEvent(new CustomEvent('pipo:stateApplied', { detail: state })); }
  async function loadDemoFixture() { try { const response = await fetch('./demo-fixture.json', { cache: 'no-store' }); if (!response.ok) throw new Error(`fixture ${response.status}`); applyState(await response.json()); } catch (error) { showToast('Demo data unavailable'); window.dispatchEvent(new CustomEvent('pipo:error', { detail: error })); } }
  function applyFilters() { const query = String(document.getElementById('search-input')?.value || '').trim().toLowerCase(); document.querySelectorAll('#view-today [data-item-id], #view-courses [data-item-id]').forEach(card => { const searchMatch = !query || card.textContent.toLowerCase().includes(query); const courseMatch = courseFilter === 'all' || card.dataset.course === courseFilter; const categoryMatch = categoryFilter === 'all' || card.dataset.category === categoryFilter; card.hidden = !(searchMatch && courseMatch && categoryMatch); }); }
  function filterCards(query) { const input = document.getElementById('search-input'); if (input && input.value !== String(query || '')) input.value = String(query || ''); applyFilters(); }
  function switchTab(tab, notify = true) { const valid = ['today', 'courses', 'settings'].includes(tab) ? tab : 'today'; ['today', 'courses', 'settings'].forEach(name => { document.getElementById(`view-${name}`)?.classList.toggle('hidden', name !== valid); const button = document.getElementById(`tab-${name}`); button?.classList.toggle('active', name === valid); button?.setAttribute('aria-current', name === valid ? 'page' : 'false'); }); const title = document.getElementById('header-title'); if (title) title.textContent = valid[0].toUpperCase() + valid.slice(1); const search = document.getElementById('search-section'); if (search) search.classList.toggle('hidden', valid === 'settings'); const input = document.getElementById('search-input'); if (input) input.placeholder = valid === 'courses' ? 'Search courses' : 'Search today'; if (notify) request('selectTab', { tab: valid }); }
  function bindActions() {
    const tabNames = ['today', 'courses', 'settings'];
    tabNames.forEach(tab => { const node = document.getElementById(`tab-${tab}`); if (node) node.addEventListener('click', () => switchTab(tab)); });
    document.querySelectorAll('button').forEach(node => {
      const label = node.textContent.trim().toLowerCase(); let action = null;
      if (label === 'sign out') action = 'signOut'; else if (label.includes('allow calendar')) action = 'requestCalendarAccess'; else if (label.includes('refresh')) action = 'refresh'; else if (label.includes('calendar')) action = 'addToCalendar'; else if (label.includes('copy')) action = 'copyDetails'; else if (label.includes('seen')) action = 'markSeen'; else if (label.includes('snooze')) action = 'snooze'; else if (label.includes('open')) action = 'openDestination'; else if (label.includes('clear')) action = 'clearCache'; else if (label.includes('update')) action = 'checkForUpdates'; else if (label.includes('diagnostic')) action = 'exportDiagnostics';
      if (label.includes('open lms in browser')) node.dataset.lmsRoot = 'true';
      if (action) node.dataset.action = action;
    });
    document.querySelectorAll('[id^="section-"] > button, [data-collapse-target]').forEach(heading => {
      const content = heading.nextElementSibling; if (!content) return; heading.setAttribute('aria-expanded', 'true'); heading.addEventListener('click', () => { content.hidden = !content.hidden; heading.setAttribute('aria-expanded', String(!content.hidden)); });
    });
    document.getElementById('search-input')?.addEventListener('input', applyFilters);
    document.getElementById('clear-search')?.addEventListener('click', () => filterCards(''));
    document.getElementById('filter-toggle')?.addEventListener('click', event => { const popover = document.getElementById('filter-popover'); const hidden = popover?.classList.toggle('hidden'); event.currentTarget.setAttribute('aria-expanded', String(!hidden)); });
    document.querySelectorAll('.cat-filter-btn').forEach(button => button.addEventListener('click', () => { const label = button.textContent.trim().toLowerCase(); categoryFilter = label.startsWith('all') ? 'all' : label.replace(/s$/, ''); applyFilters(); }));
    const settingNames = ['notificationsEnabled', 'reminderDayBefore', 'reminderHourBefore', 'assignmentNotifications', 'announcementNotifications', 'messageNotifications', 'gradeNotifications'];
    document.querySelectorAll('input.apple-switch').forEach((input, index) => { input.dataset.setting = input.dataset.setting || settingNames[index] || 'notificationsEnabled'; input.addEventListener('change', () => request('updateSettings', { [input.dataset.setting]: input.checked })); });
    document.querySelector('#view-settings input[type="range"]')?.addEventListener('change', event => request('updateSettings', { refreshMinutes: Number(event.target.value) }));
    document.querySelectorAll('select').forEach(select => select.addEventListener('change', () => request('updateChannel', { channel: select.value })));
    const inspectorButtons = document.querySelectorAll('#inspector-panel button'); inspectorButtons[0]?.addEventListener('click', closeInspectorSafe); inspectorButtons[1]?.addEventListener('click', closeInspectorSafe);
    document.addEventListener('click', event => { const menu = document.getElementById('item-context-menu'); if (!event.target.closest('#item-context-menu')) menu?.classList.add('hidden'); const actionButton = event.target.closest('[data-action]'); if (!actionButton) return; const rawAction = actionButton.dataset.action; if (rawAction.startsWith('selectTab:')) return; if (rawAction === 'closeInspector') return closeInspectorSafe(); if (rawAction === 'clearCache' && !window.confirm('Clear the saved dashboard? Pipo will fetch it again on refresh.')) return; const itemID = selectedType === 'course' ? null : selectedItem?.id; const courseID = actionButton.dataset.courseId || (selectedType === 'course' ? (selectedItem?.id || selectedItem?.courseID) : null); const payload = actionButton.dataset.lmsRoot === 'true' ? { lmsRoot: true } : courseID ? { courseID } : itemID ? { itemID } : {}; const source = actionButton.closest('#inspector-panel') ? 'inspector' : 'main'; request(rawAction, payload, source); menu?.classList.add('hidden'); event.preventDefault(); event.stopImmediatePropagation(); }, true);
    document.addEventListener('keydown', event => { if (event.key === 'Escape') { closeInspectorSafe(); document.getElementById('filter-popover')?.classList.add('hidden'); } });
  }
  window.pipoMenu = Object.freeze({ applyState, filterCards, request, switchTab, mode });
  window.addEventListener('message', event => { if (event.data?.type === 'pipo:state') applyState(event.data.state); if (event.data?.type === 'pipo:response') resolveResponse(event.data); });
  window.addEventListener('pipo-response', event => resolveResponse(event.detail));
  window.addEventListener('pipo-state', event => applyState(event.detail));
  window.addEventListener('DOMContentLoaded', () => { bindActions(); request('ui.ready'); if (mode === 'demo') loadDemoFixture(); }, { once: true });
})();
