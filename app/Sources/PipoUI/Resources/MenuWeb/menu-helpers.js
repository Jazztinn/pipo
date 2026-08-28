/* Pure renderer helpers shared by native and showcase hosts. */
(function menuHelpersRuntime(global) {
  'use strict';

  const greetingVariants = Object.freeze({
    morning: Object.freeze(['Good morning', 'Morning!', 'Rise and shine', "Hope your morning's going well"]),
    afternoon: Object.freeze(['Good afternoon', 'Afternoon!', "Hope your day's going well", "How's your day going?"]),
    evening: Object.freeze(['Good evening', 'Evening!', 'Hope you had a good day', 'Winding down?']),
    lateNight: Object.freeze(['Still up?', 'Good evening', 'Working late?', 'Late night session?'])
  });

  function hourFrom(value) {
    if (value instanceof Date) return value.getHours();
    const hour = Number(value);
    return Number.isFinite(hour) ? Math.max(0, Math.min(23, Math.floor(hour))) : 12;
  }

  function greetingPeriod(value) {
    const hour = hourFrom(value);
    if (hour >= 5 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 22) return 'evening';
    return 'lateNight';
  }

  function greetingsForHour(value) {
    return greetingVariants[greetingPeriod(value)];
  }

  function chooseGreeting(value, sample = 0) {
    const choices = greetingsForHour(value);
    const normalized = Number.isFinite(Number(sample)) ? Math.max(0, Math.min(0.999999, Number(sample))) : 0;
    return choices[Math.floor(normalized * choices.length)];
  }

  function instructorFromCourseTitle(courseTitle) {
    const title = String(courseTitle || '').trim();
    const match = title.match(/\(((?:prof(?:essor)?|dr|mr|mrs|ms|sir|ma[’']am)\.?\s+[^)]+)\)\s*$/i);
    return match?.[1]?.trim() || null;
  }

  function instructorFor(item) {
    const supplied = String(item?.instructor || '').trim();
    if (supplied) return supplied;
    return instructorFromCourseTitle(item?.courseName ?? item?.course_name) || 'Instructor unavailable';
  }

  function safeDisplay(value, fallback) {
    if (value == null || value === false) return fallback;
    const text = String(value).trim();
    if (!text || ['null', 'undefined', 'not supplied'].includes(text.toLowerCase())) return fallback;
    return text;
  }

  function gradeDisplay(grade) {
    const meaningful = item => item != null && item !== false && !['', '-', '—', 'null', 'undefined', 'not supplied'].includes(String(item).trim().toLowerCase());
    const value = (...keys) => keys.map(key => grade?.[key]).find(meaningful);
    const formatted = value('publishedGrade', 'published_grade', 'gradeformatted', 'gradeFormatted', 'grade_formatted', 'percentageformatted', 'percentageFormatted', 'percentage_formatted');
    if (formatted != null) return String(formatted).trim();
    const raw = value('graderaw', 'gradeRaw', 'grade_raw', 'grade', 'rawGrade', 'raw_grade', 'score', 'points', 'value');
    const maximum = value('grademax', 'gradeMax', 'grade_max', 'maxGrade', 'max_grade', 'max');
    if (raw != null && maximum != null) return `${String(raw).trim()} / ${String(maximum).trim()}`;
    return raw != null ? String(raw).trim() : null;
  }

  function sectionPresentation(status, title, count = 0) {
    if (count > 0) return Object.freeze({ kind: 'content', text: '', retry: false });
    const normalized = String(status || 'ready').toLowerCase();
    if (normalized === 'loading') return Object.freeze({ kind: 'loading', text: `Loading ${title.toLowerCase()}…`, retry: false });
    if (['failed', 'error', 'partialfailure', 'partial_failure'].includes(normalized)) return Object.freeze({ kind: 'error', text: `${title} could not load.`, retry: true });
    return Object.freeze({ kind: 'empty', text: `No ${title.toLowerCase()}`, retry: false });
  }

  global.pipoMenuHelpers = Object.freeze({ chooseGreeting, greetingPeriod, greetingsForHour, instructorFor, instructorFromCourseTitle, safeDisplay, gradeDisplay, sectionPresentation });
})(window);
