import copy
import unittest

from run_ios_fallback import PROBES, validate_observations


def state(pid, boot, launches, attempts):
    probes = {name: f'{name}: pass\nverified' for name in PROBES}
    probes['webview'] += f' mounted view and JavaScript roundtrip: {boot}'
    probes['dart clean state'] += f' dirty=0, boot={boot}'
    for name in ('file storage', 'sqflite'):
        probes[name] += (' previous boot verified; current boot stored' if launches == 2 else ' first boot stored')
    return dict(pid=pid, boot=f'boot token: {boot}', launches=f'launches: {launches}',
                attempts=f'restart attempts: {attempts}', dirty='dart dirty state: 0',
                allChecksPassed=True, probes=probes)


def proof(policy):
    value = dict(policy=policy, bundleID='fixture', permissionPromptObserved=True,
                 permissionPromptLabel=f'Restart Fallback {policy.title()} Would Like to Send You Notifications',
                 cleanupStoppedApp=True, **{'pass': True}, initial=state(10, 100, 1, 0))
    if policy == 'denied':
        value.update(afterDenial=state(10, 100, 1, 0), recovered=state(10, 200, 2, 3),
                     alreadyDeniedRejected=True)
    else:
        value.update(reopened=state(20, 200, 2, 1), exitObserved=True,
                     actualNotificationTapped=True, notificationLabel='Tap to reopen the example app.')
    return value


class FallbackEvidenceTests(unittest.TestCase):
    def test_both_complete_lifecycle_paths(self):
        for policy in ('denied', 'allowed'):
            validate_observations(proof(policy), 'fixture', policy)

    def test_missing_permission_tap_or_cleanup_cannot_pass(self):
        for key in ('permissionPromptObserved', 'actualNotificationTapped', 'exitObserved', 'cleanupStoppedApp'):
            value = proof('allowed')
            value[key] = False
            with self.assertRaises(ValueError):
                validate_observations(value, 'fixture', 'allowed')
        value = proof('allowed')
        value['permissionPromptLabel'] = 'Another app would like to send notifications'
        with self.assertRaises(ValueError):
            validate_observations(value, 'fixture', 'allowed')

    def test_wrong_process_or_stale_boot_cannot_count_as_recovery(self):
        for policy, key, field, wrong in [('allowed', 'reopened', 'pid', 10),
                                           ('denied', 'recovered', 'pid', 20),
                                           ('denied', 'afterDenial', 'boot', 'boot token: 999'),
                                           ('allowed', 'reopened', 'boot', 'boot token: 100')]:
            value = proof(policy)
            value[key][field] = wrong
            with self.assertRaises(ValueError):
                validate_observations(value, 'fixture', policy)

    def test_missing_saved_data_or_current_webview_cannot_pass(self):
        for probe_name in ('file storage', 'sqflite', 'webview'):
            value = proof('allowed')
            value['reopened']['probes'][probe_name] = f'{probe_name}: pass\nunrelated result'
            with self.assertRaises(ValueError):
                validate_observations(value, 'fixture', 'allowed')
        value = copy.deepcopy(proof('denied'))
        value['recovered']['probes'].pop('http')
        with self.assertRaises(ValueError):
            validate_observations(value, 'fixture', 'denied')


if __name__ == '__main__':
    unittest.main()
