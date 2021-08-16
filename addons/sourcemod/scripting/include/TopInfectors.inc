/**
 * This is the include file for TopInfectors
 * To check that TopInfectors is installed and running, verify that the "TopInfectors" library exists
 */

#if defined _TopInfectors_included
    #endinput
#endif
#define _TopInfectors_included

/**
 * Check if the given client is top infector
 *
 * @param client     Any valid client index.
 * @return           Returns -1 if the client is not a top infector, otherwise it returns its top infector position.
 */
native int IsTopInfector(int client);

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
}
#endif