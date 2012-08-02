package edu.berkeley.myberkeley.migrators;

import java.util.Map;

import org.apache.felix.scr.annotations.Component;
import org.apache.felix.scr.annotations.Reference;
import org.apache.felix.scr.annotations.Service;
import org.sakaiproject.nakamura.api.lite.ClientPoolException;
import org.sakaiproject.nakamura.api.lite.PropertyMigrator;
import org.sakaiproject.nakamura.api.lite.Repository;
import org.sakaiproject.nakamura.api.lite.Session;
import org.sakaiproject.nakamura.api.lite.StorageClientException;
import org.sakaiproject.nakamura.api.lite.accesscontrol.AccessDeniedException;
import org.sakaiproject.nakamura.api.lite.content.Content;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.common.collect.ImmutableMap;

/**
 * Originally had bigger plans for this, but will migrate the loaded dashboard widget "mylinks"
 * to the newer version "quicklinks". Required a migrator since the previous widget cannot be removed
 * and after renaming/purging from devwidgets, would be near impossible for an end user to handle this
 * change themselves.
 */
@Service
@Component
public class MyLinksQuicklinksMigrator implements PropertyMigrator { 

    @Reference
    transient protected Repository repository;

    //contains the regex patterns for matching the path for dashboard widgets.
    private static final String loadedMyLinksWidgetLocation = "a:\\d+/private/privspace/id[\\w/]+/dashboard/[\\w/]+array[\\w]+";

    private static final Logger LOGGER = LoggerFactory.getLogger(MyLinksQuicklinksMigrator.class);

    @Override
    public boolean migrate(String rid, Map<String, Object> properties) {	
        if (properties == null) {
            return false;
        }

        boolean modified = false;

        if (properties.containsKey("_path")) {
            Session session = null;
            try {
                session = repository.loginAdministrative();
                String path = properties.get("_path").toString();
                Content content = session.getContentManager().get(path);

                //should move everyone's preloaded mylinks widget to quicklinks. 
                //Ignoring data storage issues since quicklinks widget will handle data migration.
                if (content != null 
                        && content.getPath().matches(loadedMyLinksWidgetLocation)
                        && content.hasProperty("name") 
                        && content.getProperty("name").toString().equalsIgnoreCase("mylinks")) {
                    content.setProperty("name", "quicklinks");
                    if (properties.containsKey("name") 
                            && properties.get("name").toString().equalsIgnoreCase("mylinks")) {
                        LOGGER.info("Path: " + path + " modified, key:\"name\", value: quicklinks");
                        properties.put("name", "quicklinks");
                    }
                    modified = true;
                }
            } catch (AccessDeniedException e) {
                LOGGER.error(e.getMessage(), e);
            } catch (ClientPoolException e) {
                LOGGER.error(e.getMessage(), e);
            } catch (StorageClientException e) {
                LOGGER.error(e.getMessage(), e);
            } finally {
                if (session != null) {
                    try {
                        session.logout();
                    } catch (ClientPoolException e) {
                        LOGGER.error("Unexpected exception logging out of session", e);
                    }
                }
            }
        }

        return modified;
    }

    @Override
    public String[] getDependencies() {
        return new String[0];
    }

    @Override
    public String getName() {
        return MyLinksQuicklinksMigrator.class.getName();
    }

    @Override
    public Map<String, String> getOptions() {
        return ImmutableMap.of(PropertyMigrator.OPTION_RUNONCE, "false");
    }

}
