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

  global.pipoMenuHelpers = Object.freeze({ chooseGreeting, greetingPeriod, greetingsForHour, instructorFor, instructorFromCourseTitle });
})(window);
