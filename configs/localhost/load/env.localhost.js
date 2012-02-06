define(["config/config"], function(config) {
    config.isDev = false;

    // Tracking and statistics
    config.Tracking = {
        GoogleAnalytics: {
            WebPropertyID : "UA-21809393-3"
        }
    };
    config.showSakai2=true;
    config.useLiveSakai2Feeds=true;
    config.hybridCasHost="xgrid-dev.media.berkeley.edu";    
});
