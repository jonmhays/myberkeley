define(["config/config"], function(config) {
    config.isDev = true;
    // Tracking and statistics
    config.Tracking = {
        GoogleAnalytics: {
            WebPropertyID : "UA-21809393-3"
        }
    };
    config.showSakai2=true;
    config.useLiveSakai2Feeds=true;
    config.hybridCasHost="sakai-dev.berkeley.edu";
});
