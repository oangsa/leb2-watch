const iosAssignmentRefreshTaskIdentifier =
    'dev.oangsa.leb2watch.assignment-refresh';

const iosBackgroundRefreshExpirationChannel =
    'dev.oangsa.leb2watch/background_refresh_expiration';

const iosBackgroundExecutionBudget = Duration(seconds: 25);
const iosBackgroundExpirationAttachTimeout = Duration(seconds: 1);
const iosBackgroundExpirationDetachTimeout = Duration(milliseconds: 500);
