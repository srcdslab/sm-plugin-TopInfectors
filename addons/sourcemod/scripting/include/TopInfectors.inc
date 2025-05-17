/**
 * This is the include file for TopInfectors
 * To check that TopInfectors is installed and running, verify that the "TopInfectors" library exists
 */

#if defined _TopInfectors_included
    #endinput
#endif
#define _TopInfectors_included

#define TopInfectors_V_MAJOR   "1"
#define TopInfectors_V_MINOR   "5"
#define TopInfectors_V_PATCH   "4"

#define TopInfectors_VERSION   TopInfectors_V_MAJOR..."."...TopInfectors_V_MINOR..."."...TopInfectors_V_PATCH

/**
 * DEPRECATED NATIVE
 * Check if the given client is top infector
 *
 * @param client     Any valid client index.
 * @return           Returns -1 if the client is not a top infector, otherwise it returns its top infector position.
 */
#pragma deprecated Use TopInfectors_GetClientRank() instead.
native int IsTopInfector(int client);

/**
 * Check if the given client is top infector
 *
 * @param client     Any valid client index.
 * @return           Returns -1 if the client is not ingame/ranked, otherwise it returns its top defender position.
 */
native int TopInfectors_GetClientRank(int client);

public SharedPlugin __pl_TopInfectors = 
{
	name = "TopInfectors",
	file = "TopInfectors.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_TopInfectors_SetNTVOptional()
{
	MarkNativeAsOptional("TopInfectors_IsTopInfector");
	MarkNativeAsOptional("TopInfectors_GetClientRank");
}
#endif