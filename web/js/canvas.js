// Canvas REST client. Same two calls as the iOS app: the to-do feed for
// everything outstanding, then per-course assignments for the richer detail.
//
// The Canvas API sends no Access-Control-Allow-Origin header and its OPTIONS
// preflight 404s, so a plain web page cannot call it — the browser blocks the
// request before Canvas ever sees it. Running as a Chrome extension is what
// makes these calls possible, because host_permissions exempts them from CORS.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.CDT = Object.assign(root.CDT || {}, factory());
}(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  class CanvasError extends Error {
    constructor(kind, message) {
      super(message);
      this.name = 'CanvasError';
      this.kind = kind;   // 'blocked' | 'auth' | 'network' | 'server'
      this.requiresReauthentication = kind === 'auth';
    }
  }

  function inferType(assignment) {
    const types = assignment.submission_types || [];
    const name = (assignment.name || '').toLowerCase();
    const named = /exam|midterm|final/.test(name) ? 'exam'
      : /quiz|test/.test(name) ? 'quiz'
      : /discussion|forum|board/.test(name) ? 'discussion'
      : /assignment|homework|paper/.test(name) ? 'assignment'
      : 'other';

    if (assignment.quiz_id != null || assignment.is_quiz_assignment || types.includes('online_quiz')) {
      return named === 'exam' ? 'exam' : 'quiz';
    }
    if (types.includes('discussion_topic')) return 'discussion';
    return named === 'other' ? 'assignment' : named;
  }

  function isSubmitted(submission) {
    if (!submission) return null;
    if (submission.submitted_at) return true;
    return ['graded', 'submitted', 'complete'].includes(submission.workflow_state);
  }

  function stripHtml(html) {
    if (!html) return null;
    const text = String(html).replace(/<[^>]*>/g, ' ').replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&').replace(/&lt;/gi, '<').replace(/&gt;/gi, '>')
      .replace(/&#8211;|&ndash;/gi, '–').split(/\s+/).filter(Boolean).join(' ');
    return text || null;
  }

  function toItem(assignment, courseName, courseCode, host) {
    if (!assignment || !assignment.due_at) return null;
    const fallback = assignment.course_id
      ? 'https://' + host + '/courses/' + assignment.course_id + '/assignments/' + assignment.id
      : null;
    return {
      source: 'canvas',
      sourceItemId: 'assignment-' + assignment.id,
      courseName: courseName || 'Canvas',
      courseCode: courseCode || '',
      title: (assignment.name || '').trim() || 'Untitled assignment',
      type: inferType(assignment),
      dueDate: new Date(assignment.due_at).toISOString(),
      url: assignment.html_url || fallback,
      details: stripHtml(assignment.description),
      isCompleted: isSubmitted(assignment.submission)
    };
  }

  // Prefer whichever entry carries the richer course label: the to-do feed has
  // only a display name, the per-course call also has the code.
  function merge(groups) {
    const byId = new Map();
    for (const group of groups) {
      for (const item of group) {
        const existing = byId.get(item.sourceItemId);
        if (!existing) { byId.set(item.sourceItemId, item); continue; }
        if (!existing.courseCode) existing.courseCode = item.courseCode;
        if (!existing.courseName || existing.courseName === 'Canvas') existing.courseName = item.courseName;
        if (!existing.details) existing.details = item.details;
        if (!existing.url) existing.url = item.url;
        if (existing.isCompleted == null) existing.isCompleted = item.isCompleted;
      }
    }
    return Array.from(byId.values()).sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate));
  }

  function nextPageUrl(linkHeader) {
    if (!linkHeader) return null;
    for (const part of linkHeader.split(',')) {
      const segments = part.split(';');
      const rel = segments.slice(1).map((s) => s.trim().toLowerCase());
      if (!rel.includes('rel="next"') && !rel.includes('rel=next')) continue;
      return segments[0].trim().replace(/^<|>$/g, '');
    }
    return null;
  }

  function createClient(host, token, fetchImpl) {
    const doFetch = fetchImpl || (typeof fetch === 'function' ? fetch.bind(null) : null);

    async function request(url) {
      let response;
      try {
        response = await doFetch(url, {
          headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' }
        });
      } catch (error) {
        // A CORS refusal surfaces as an opaque TypeError, indistinguishable
        // from being offline — so say what is actually most likely.
        throw new CanvasError(
          'blocked',
          'The browser blocked the request to Canvas. Canvas does not allow direct calls from web pages; ' +
          'load this as a Chrome extension (see the README) to sync.'
        );
      }

      if (response.status === 401) {
        throw new CanvasError('auth', 'Canvas rejected your access token. Generate a new one and paste it in Settings.');
      }
      if (response.status === 403) {
        const body = await response.text().catch(() => '');
        throw new CanvasError(
          'server',
          /rate limit/i.test(body)
            ? 'Canvas is rate limiting this account. Try again in a few minutes.'
            : 'Canvas denied that request. Your token may not have the right permissions.'
        );
      }
      if (!response.ok) {
        throw new CanvasError('server', 'Canvas returned an error (' + response.status + '). Try again shortly.');
      }
      return { data: await response.json(), link: response.headers.get('Link') };
    }

    async function paged(path, query) {
      let url = 'https://' + host + path + (query ? '?' + query : '');
      const pages = [];
      for (let guard = 0; guard < 20 && url; guard += 1) {
        const result = await request(url);
        pages.push(result.data);
        url = nextPageUrl(result.link);
      }
      return pages.flat();
    }

    return {
      async verifyToken() {
        const result = await request('https://' + host + '/api/v1/users/self');
        return result.data.short_name || result.data.name || 'your Canvas account';
      },

      async fetchDeadlines() {
        const todo = await paged('/api/v1/users/self/todo', 'per_page=100');
        const fromTodo = todo
          .filter((entry) => !entry.type || entry.type === 'submitting')
          .map((entry) => toItem(entry.assignment, entry.context_name, '', host))
          .filter(Boolean);

        // The per-course pass adds codes and descriptions. If it fails, the
        // to-do results still stand rather than the whole sync failing.
        let fromCourses = [];
        try {
          const courses = await paged(
            '/api/v1/courses',
            'enrollment_state=active&enrollment_type=student&state[]=available&per_page=100'
          );
          for (const course of courses) {
            if (course.access_restricted_by_date || !course.name) continue;
            try {
              const assignments = await paged(
                '/api/v1/courses/' + course.id + '/assignments',
                'bucket=upcoming&include[]=submission&order_by=due_at&per_page=100'
              );
              fromCourses = fromCourses.concat(
                assignments.map((a) => toItem(a, course.name, course.course_code, host)).filter(Boolean)
              );
            } catch (_) { /* one restricted course must not sink the pass */ }
          }
        } catch (_) { /* keep the to-do results */ }

        return merge([fromTodo, fromCourses]);
      }
    };
  }

  return { createClient, CanvasError, toItem, merge, nextPageUrl, inferType, isSubmitted };
}));
