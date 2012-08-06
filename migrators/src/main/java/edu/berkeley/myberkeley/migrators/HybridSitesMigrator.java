package edu.berkeley.myberkeley.migrators;

import java.util.HashSet;
import java.util.Iterator;
import java.util.Map;

import org.apache.felix.scr.annotations.Component;
import org.apache.felix.scr.annotations.Reference;
import org.apache.felix.scr.annotations.Service;
import org.apache.sling.commons.json.JSONException;
import org.apache.sling.commons.json.JSONObject;
import org.sakaiproject.nakamura.api.lite.ClientPoolException;
import org.sakaiproject.nakamura.api.lite.PropertyMigrator;
import org.sakaiproject.nakamura.api.lite.Repository;
import org.sakaiproject.nakamura.api.lite.Session;
import org.sakaiproject.nakamura.api.lite.StorageClientException;
import org.sakaiproject.nakamura.api.lite.accesscontrol.AccessDeniedException;
import org.sakaiproject.nakamura.api.lite.content.Content;
import org.sakaiproject.nakamura.api.lite.content.ContentManager;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.common.collect.ImmutableMap;
import com.google.common.collect.Maps;
import com.google.common.collect.Sets;

/**
 * Re-enables hybrid menus/widgets for OAE 1.4. For users with accounts and privspace stores created before the change to
 * re-enable hybrid, this migrator attempts to:
 * 1) Insert the "my bspace favorites" widget into the dashboard, if it does not exist. It will naturally drop it at the
 *    end of the first column.
 * 2) Insert the My bspace sites into structure0, which is used for the left hand navigation menu.
 * 3) Insert the datastore for the "my bSpace sites" into privstore, which is used for rendering the page.
 * 
 * The items above were identified by analyzing the git commit here: https://github.com/ets-berkeley-edu/3akai-ux/commit/859c563ed869e0a5bb7921441dadfb9473e8125
 * which details the fields that are touched when creating a new user with hybrid enabled.
 *
 */
@Service
@Component
public class HybridSitesMigrator implements PropertyMigrator {

    @Reference
    transient protected Repository repository;

    /** Regex pattern for the users' dashboard column(s). */
    private static final String userDashboardLocationForHybrid = "a:\\d+/private/privspace/id[\\w/]+/dashboard/columns";
    // ((/~)|(a:))\d+/private/privspace
    
    /** Regex pattern for privspace. */
    private static final String privSpace = "a:\\d+/private/privspace";
    
    private static final Logger LOGGER = LoggerFactory.getLogger(HybridSitesMigrator.class);
    
    private static int userDashboardCounter = 0;

    private static int userPrivspaceCounter = 0;
    
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
                ContentManager contentManager = session.getContentManager();
                Content content = contentManager.get(path);
                

                //inserting a mysakai2/"my bSpace favorites" widget location into everyone's dashboards, IF it does not exist
                if (content != null && content.getPath().matches(userDashboardLocationForHybrid)) {
                    LOGGER.info("processing dashboard location: {} ", content.getPath());
                    userDashboardCounter++;
                    LOGGER.info("userDashboardCounter: {}", userDashboardCounter);
                    boolean hybridWidgetExists = containsHybridWidget(content);
                    
                    if (!hybridWidgetExists) {
                        modified = insertHybridWidget(session.getContentManager(), content);
                        if (modified) {
                            LOGGER.info("Inserted widget into {} dashboard", content.getPath());
                        }
                    }
                    return modified;
                }
                
                //insert the "My bSpace sites" into the lhnavigation menu and set up datastores.
                //XXX: section is worth extracting into a separate method...
                if (content != null && content.getPath().matches(privSpace)) {
                    LOGGER.info("processing privspace location: {}", content.getPath());
                    userPrivspaceCounter++;
                    LOGGER.info("userPrivspaceCounter: {}", userPrivspaceCounter);
                    String searchSakaiId = null;
                    if (content.hasProperty("structure0")) {
                        JSONObject structure0 = null;
                        try {
                            structure0 = new JSONObject((String) content.getProperty("structure0"));
                        } catch (JSONException e1) {
                            LOGGER.error("Could not parse structure0 into JSON");
                        }
                        Iterable<String> privChildren = content.listChildPaths();
                        JSONObject structure0JsonAdditions = setupSakai2sitesStructure(privChildren);
                        if (structure0 != null && structure0JsonAdditions != null) {
                            //extract searchsakaiId from JSONObject
                            JSONObject sakai2sites;
                            try {
                                sakai2sites = (JSONObject) structure0JsonAdditions.get("sakai2sites");
                                structure0.put("sakai2sites", sakai2sites);
                                String structure0String = structure0.toString();
                                searchSakaiId = sakai2sites.getString("_ref");
                                
                                content.setProperty("structure0", structure0String);
                                properties.put("structure0", structure0String);
                                contentManager.update(content);
                                modified = true;
                                LOGGER.info("Structure0: " + structure0String + " inserted new entry my bSpace sites on lhnavigation menu.");
                            } catch (JSONException e) {
                                LOGGER.error("Failed to extract searchSakaiId from structure0 JSONObject");
                            }
                        }
                    } else {
                        LOGGER.error("Missing structure0 object");
                    }
                    
                    //need to setup new datastore for sakai2sites
                    if (searchSakaiId != null) {
                        String elementsPath = new StringBuffer(content.getPath()).append("/")
                                .append(searchSakaiId).append("/rows/__array__0__/columns/__array__0__/elements/__array__0__").toString();
                        Map<String, Object> elementsContent = Maps.newHashMap();
                        String id = searchSakaiId.substring(0, searchSakaiId.length()-1) + "6";
                        elementsContent.put("id", id);
                        elementsContent.put("type", "searchsakai2");
                        Content elements = new Content(elementsPath, elementsContent);
                        
                        Map<String, Object> columnsContent = Maps.newHashMap();
                        String columnsPath = new StringBuffer(content.getPath()).append("/")
                                .append(searchSakaiId).append("/rows/__array__0__/columns/__array__0__").toString();
                        columnsContent.put("width", 1);
                        Content columns = new Content(columnsPath, columnsContent);
                        
                        Map<String, Object> rowsContent = Maps.newHashMap();
                        String rowsPath = new StringBuffer(content.getPath()).append("/")
                                .append(searchSakaiId).append("/rows/__array__0__").toString();
                        rowsContent.put("id", "id8965114");
                        Content rows = new Content(rowsPath, rowsContent);
                        
                        contentManager.update(elements);
                        contentManager.update(columns);
                        contentManager.update(rows);
                    }
                    
                    return modified;
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

    /**
     * Create the JSONObject structure for the "sakai2sites" entry in structure0. 
     * 
     * @param childPaths childPaths of the privstructure. Needed to iterate through to ensure no collisions with generated widgetID for store.
     * @return JSONObject only for the "sakai2sites" key to be inserted into structure0 or NULL if no modifications need to be made.
     */
    private JSONObject setupSakai2sitesStructure(final Iterable<String> childPaths) {
        try {
            JSONObject structure0Json = new JSONObject();
            if (structure0Json != null && !structure0Json.has("sakai2sites")) {
                //generate a linking sakaiID datastore.
                HashSet<String> existingIDs = Sets.newHashSet();
                for (String childPath : childPaths) {
                    String[] results = childPath.split(privSpace + "/");
                    for(String result : results) {
                        existingIDs.add(result);
                    }
                }
                String searchSakaiId = null;
                //Will attempt <sanityBreak> times to generate a non-colliding widgetId.
                int sanityBreak = 1000;
                while (sanityBreak > 0) {
                    String newID = generateNewId() + "2345";
                    if (!existingIDs.contains(newID)) {
                        searchSakaiId = newID;
                        break;
                    } else {
                        sanityBreak--;
                    }
                }
                
                if (searchSakaiId != null) {
                    JSONObject main = new JSONObject();
                    main.put("_ref", searchSakaiId);
                    main.put("_order", 0);
                    main.put("_title", "My Sakai 2 Sites");
                    
                    JSONObject sakai2sites = new JSONObject();
                    sakai2sites.put("_ref", searchSakaiId);
                    sakai2sites.put("_title", "My bSpace sites");
                    sakai2sites.put("_order", 2);
                    sakai2sites.put("_canEdit", true);
                    sakai2sites.put("_reorderOnly", true);
                    sakai2sites.put("_nonEditable", true);
                    sakai2sites.put("main", main);
                    
                    structure0Json.put("sakai2sites", sakai2sites);
                    return structure0Json;
                } else {
                    //log error generating id.
                    LOGGER.error("Could not generate a non-colliding _ref id");
                }
            }
        } catch (JSONException e) {
            LOGGER.error("structure0 not a JSON object", e);
        }
        
        //no additions need to be made to the structure0 object.
        return null;
    }

    /**
     * Insert a "My bSpace favorites" widget into the dashboard.
     * 
     * @param contentManager all powerful content manager authenticated as admin to muck with everyone's privspace.
     * @param dashboardRoot root content location for the beginning of the dashboard layout, used to iterate through and determine
     *      the existence of a "My bSpace favorites" widget.
     * @return whether or not a hybrid widget was inserted into the dashboard.
     * @throws AccessDeniedException on issues updating content with contentManager
     * @throws StorageClientException on issues updating content with contentManager
     */
    private boolean insertHybridWidget(final ContentManager contentManager,
            final Content dashboardRoot) throws AccessDeniedException, StorageClientException {
        Iterator<Content> dashboardColumns = dashboardRoot.listChildren().iterator();
        if (!dashboardColumns.hasNext()) {
            //something's probably screwed up with privspace, not going to bother inserting.
            LOGGER.error("Could not find columns in dashboard childen to insert hybrid widget.");
            return false;
        } else {
            Content dashboardColumn = dashboardColumns.next();
            String pathPrefix = dashboardColumn.getPath();
            int numChildren = 0;
            for (@SuppressWarnings("unused") Content columnItems : dashboardColumn.listChildren()) {
                numChildren++;
            }
            
            Map<String, Object> contentEntries = Maps.newHashMap();
            String newEntryPath = new StringBuffer(pathPrefix).append("/__array__").append(numChildren).append("__").toString();
            Content newHybridEntry = new Content(newEntryPath,  contentEntries);
            String newUID = generateNewId() + "1234";
            newHybridEntry.setProperty("uid",  newUID);
            newHybridEntry.setProperty("visible", "block");
            newHybridEntry.setProperty("name", "mysakai2");
            
            contentManager.update(newHybridEntry);
            LOGGER.info("Path: " + newEntryPath + " inserted new entry for mysakai2 widget");
            return true;   
        }
    }

    /**
     * Determine if a "My bSpace Favorites" widget exists in the content elements.
     * 
     * @param content root content location for the beginning of the dashboard layout, used to iterate through and determine
     *      the existence of a "My bSpace favorites" widget.
     * @return true/false, on whether or not the "My bSpace Favorites" widget already exists.
     */
    private boolean containsHybridWidget(Content content) {
        Iterable<Content> dashboardItems = content.listChildren();
        boolean containsHybridWidget = false;
        for(Content dashboardColumns : dashboardItems) {
            if (containsHybridWidget) {
                break;
            }
            Iterable<Content> dashboardElements = dashboardColumns.listChildren();
            for (Content dashboardItem : dashboardElements) {
                if (dashboardItem.getProperty("name") != null
                        && dashboardItem.getProperty("name").toString().equalsIgnoreCase("mysakai2")) {
                    containsHybridWidget = true;
                    break;
                }
            }
        }
        return containsHybridWidget;
    }
    
    /**
     * Generate a widgetID. Found this somewhere in the 3akai-ux sakai libraries and copied the logic.
     * @return a new randomly generated widgetId. Could possibly collide with previous widgetIds for a user's space.
     */
    private String generateNewId() {
        return new StringBuffer("id").append(Math.round((Math.random() * 10000000))).toString();
    }
    
    @Override
    public String[] getDependencies() {
        return new String[0];
    }

    @Override
    public String getName() {
        return HybridSitesMigrator.class.getName();
    }

    @Override
    public Map<String, String> getOptions() {
        return ImmutableMap.of(PropertyMigrator.OPTION_RUNONCE, "false");
    }

}
