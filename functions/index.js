const functions = require('firebase-functions');
const admin = require('firebase-admin');

try { admin.initializeApp(); } catch (e) {}

// Sends a push to refresh widgets on all devices
exports.onWidgetChanged = functions.database.ref('/notes/widget').onWrite(async (change, ctx) => {
  const after = change.after.val() || {};
  const display = (after.display_text || '').toString();
  const title = (after.selected_note_id || '').toString();
  const msg = {
    topic: 'widget_updates',
    data: {
      event: 'widget_updated',
      id: title,
    },
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '10', 'apns-push-type': 'background' },
      payload: { aps: { 'content-available': 1 } }
    }
  };
  await admin.messaging().send(msg);
});

// Sends a user-visible notification when any note content changes
exports.onAnyNoteChanged = functions.database.ref('/notes/shared/{id}').onWrite(async (change, ctx) => {
  const id = ctx.params.id;
  const after = change.after.val() || {};
  const title = (after.title || '(Untitled)').toString();
  const body = 'A shared note was updated';
  const msg = {
    topic: 'notes_updates',
    notification: { title: `Note updated: ${title}`, body },
    data: { event: 'note_updated', id },
    android: { priority: 'high' }
  };
  await admin.messaging().send(msg);
});

