def seconds_per_day: 86400;

def days_between($from; $to): (($to | fromdate) - ($from | fromdate)) / seconds_per_day;

def board_item($project): first(.project_items[] | select(.project == $project)) // null;

def on_board($project): board_item($project) != null;

def has_label($name): any(.labels[]; . == $name);
