from ezr import the, DATA, csv, rows, half_mean, row

def half_mean_edit(self:DATA, rows:rows, left, right, sortp=False) -> tuple[rows,rows,row,row,float]:
#   left,right = self.twoFar(rows, sortp=sortp)
  lefts,rights = [],[]
  for row in rows: 
    (lefts if self.dist(row,left) <= self.dist(row,right) else rights).append(row)
  return self.dist(left,lefts[-1]),lefts, rights

DATA.half_mean_edit = half_mean_edit

def compare_splits(d: DATA, rows: rows):
    # Run the original half_mean function
    dist_orig, lefts_orig, rights_orig, left_orig, right_orig = d.half_mean(rows, sortp=False)
    
    # Run your edited half_mean_edit function
    dist_edit, lefts_edit, rights_edit = d.half_mean_edit(rows, left_orig, right_orig, sortp=False)
    
    # Compare the number of elements in lefts and rights
    left_diff = len(lefts_orig) - len(lefts_edit)
    right_diff = len(rights_orig) - len(rights_edit)
    
    # Compare the distances
    dist_diff = abs(dist_orig - dist_edit)
    
    # Return a similarity score
    return {
        "left_diff": left_diff,
        "right_diff": right_diff,
        "dist_diff": dist_diff,
        # "left_match": left_orig == left_edit,
        # "right_match": right_orig == right_edit
    }

# Example usage:
d = DATA().adds(csv("data/optimize/config/SS-B.csv"))  # Use appropriate data path
rows = d.rows
score = compare_splits(d, rows)

# Display the comparison score
print(f"Left difference: {score['left_diff']}")
print(f"Right difference: {score['right_diff']}")
print(f"Distance difference: {score['dist_diff']}")
# print(f"Left node match: {score['left_match']}")
# print(f"Right node match: {score['right_match']}")
