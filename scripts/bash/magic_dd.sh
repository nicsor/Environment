NSA_PRJ_ROOT_FILE=".nsa_prj_root_dir"
NSA_PRJ_CACHE_FILE=".nsa_prj_file_cache"

# Lists all paths in the current path that contain a defined pattern.
# $1 pattern to search for.
function search_path()
{
  if [ -z "$1" ]; then
    echo "Usage: search_path <pattern>"
    return
  fi

  local pattern=$1
  echo -e '->\t\t\t'file://$PWD
  ls -lad --human-readable `find $PWD` | awk '{printf("%s %s %s %s\tfile://%s (%s)\n", $1, $6, $7, $8, $9, $5); }' | grep ${pattern}
}

# Find the first index of a pattern in a string.
# $1 is the pattern to search for
# $2 is the source string in which to search the pattern
# Outputs the index if found. Outputs nothing otherwise
function first_index_of()
{
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: first_index_of <pattern> <input>"
    return
  fi

  local pattern=$1
  local input=$2  
  local result=${input/${pattern}*/}

  [ ${#result} = ${#input} ] || echo ${#result}
}

# Extract a path from a string delimited by './' and ':'
# Note: Considering patterns like 'Binary file ./bla-bla matches' to be invalid
# $1 is the input string
# Outputs the extracted path if a valid match is found
function extract_relative_path()
{
  if [ -z "$1" ]; then
    echo "Usage: extract_relative_path <input>"
    return
  fi

  local input=$1
  local startOffset=`first_index_of "./" "$input"`
  if [ ! -z "$startOffset" ] && [ "$startOffset" == "0" ]; then
    # Remove the './'
    input=${input:2}

    local stopOffset=`first_index_of ":" "$input"`
    if [ ! -z "$stopOffset" ]; then
      # Remove trailing part of the string
      echo ${input:0:$stopOffset}
    fi
  fi
}

# Print a given text with the passed pattern highlighted
# $1 is the input text
# $2 is the pattern to be highlighted
# $3 is the color for the highlight
function print_with_highlight()
{
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: print_with_highlight <text> <pattern>"
    return
  fi

  local text="$1"
  local highlight="$2"
  local color="$3"

  # Set a default colot if not specified
  if [ "$color" = "" ]; then
    color='\e[1;91m'
  fi

  while true
  do
    if [ -z "$text" ]; then
      break
    fi

    local searchIndex=`first_index_of "$highlight" "$text"`

    if [ -z "$searchIndex" ]; then
      echo -n "${text:0}"
      break
    fi

    # Output highlighted data
    echo -n "${text:0:$searchIndex}"
    echo -en "$color"
    echo -n $highlight
    echo -en "\033[1m\033[0m"

    # Remove processed part
    text=${text:$(($searchIndex + ${#highlight}))}
  done

  # Output new line
  echo ""
}

# List all files in the current path matching a defined pattern
# $1 is the searched pattern
function search_files()
{
  if [ -z "$1" ]; then
    echo "Usage: search_files <pattern>"
    return
  fi

  local pattern=$1

  grep -Hrn "$pattern" .
}

# List all files in the current path matching a defined pattern
# with some additional grouping of the output
# $1 is the searched pattern
function search_files_grouped()
{
  if [ -z "$1" ]; then
    echo "Usage: search_files_grouped <pattern>"
    return
  fi

  local pattern=$1

  local list=`grep -Hrn "$pattern" .`
  local previousPath=""
  local currentDirectory=$(pwd)

  while read -r line; do
    if [ -z "$line" ]; then
      continue
    fi

    local relativePath=`extract_relative_path "$line"`

    # Print the full file path if the pattern is found in a new file
    if [ "$previousPath" != "$relativePath" ]; then
      local filePath="file:$currentDirectory/$relativePath"

      previousPath=$relativePath

      echo ""
      print_with_highlight "$filePath" "$relativePath" '\e[1;4m'
    fi

    # Remove relative path from the entry. keep only line number and content
    # example: ./logger.h:121: something.
    if [ ! -z "$relativePath" ]; then
      line=${line:$(( ${#relativePath} + 3 ))}
    fi

    echo -n "    "
    print_with_highlight "$line" "$1"
  done <<< "$list"
}

# List the path to the project root
# It is assumed that the project root shall contain a specific file
function get_project_root()
{
  local originalPath=`pwd`
  local projectPath=`pwd`

  # Check if the file has been found or move to the upper directory
  while [ ! -f "$projectPath/$NSA_PRJ_ROOT_FILE" ] && [ "$projectPath" != "/" ]; do
    cd ..
    projectPath=`pwd`
  done

  # Return to the original path
  cd $originalPath

  # Output the found project path
  if [ -f "$projectPath/$NSA_PRJ_ROOT_FILE" ]; then
    echo $projectPath
  fi
}

# Sets the current path as a project root
function set_project_root()
{
   touch $NSA_PRJ_ROOT_FILE
}

# Change directory to the root folder
# Should be inside project path. If the project root is not found,
# it moves to the home folder.
function go_root()
{
    cd `get_project_root`
}

function reindex_project()
{
  local rootDirectory=$(get_project_root)

  if [ ! -z "$rootDirectory" ]; then
    if [ -f $rootDirectory/$NSA_PRJ_CACHE_FILE ]; then
      rm $rootDirectory/$NSA_PRJ_CACHE_FILE
    fi

    echo -n "Preparing index ... "
    (cd $rootDirectory;
    find . -name .svn -prune -o -name .repo -prune -o -type f > $NSA_PRJ_CACHE_FILE)
    echo "Complete"
  else
    echo "Not currently within a project"
  fi
}

# Change directory to the path where the passed pattern is found
# Should be inside a project path.
# It shall index the files in the project if not already indexed.
# Subsequent calls to this method shall use the cached path list.
function go_dir()
{
  if [ -z "$1" ]; then
    echo "Usage: godir <pattern>"
    return
  fi

  local rootDirectory=$(get_project_root)

  if [ -z "$rootDirectory" ]; then
    echo "Not currently within a project"
    return
  fi

  # Create search cache
  if [ ! -f $rootDirectory/$NSA_PRJ_CACHE_FILE ]; then
    reindex_project
  fi

  # Get list of paths that match the pattern
  local lines=`grep "$1" $rootDirectory/$NSA_PRJ_CACHE_FILE | sed -e 's/\/[^/]*$//' | sort | uniq`
  local entriesCount=${#lines[@]}

  if [ $entriesCount = 0 ]; then
    # No choices found
    echo "Not listed"
  elif [ $entriesCount = 1 ]; then
    # Only one choice available
    cd $rootDirectory/${lines[0]}
  else
    # Multiple choices available
    while : 
    do
      local index=1
      local filePath

      # List choices
      for filePath in ${lines[@]}; do
        printf "%5s) %s\n" $index $filePath
        index=`$index + 1`
      done

      echo
      echo -n "Select one: "
      local choice
      read choice

      # Check if a valid choicd was selected
      if [ $choice -gt $entriesCount ] || [$choice -lt 1 ]; then
        echo "Select a number as listed below: "
        continue
      fi

      # Switch to the selected choice
      local selectedPath=${lines[$($choice-1)]}
      cd $rootDirectory/$selectedPath
      break;
    done
  fi
}
