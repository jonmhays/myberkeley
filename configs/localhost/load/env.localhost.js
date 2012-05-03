define(["config/config"], function(config) {
    config.isDev = true;

    // Tracking and statistics
    config.Tracking = {
        GoogleAnalytics: {
            WebPropertyID : "UA-21809393-3"
        }
    };
    config.showSakai2=false;
    config.useLiveSakai2Feeds=false;
});
