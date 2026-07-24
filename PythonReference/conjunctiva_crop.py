from __future__ import annotations

from collections.abc import Sequence


def lower_quarter(
    face_bounding_box: Sequence[float],
    eye_points: Sequence[Sequence[float]],
) -> tuple[float, float, float, float]:
    if len(face_bounding_box) != 4 or not eye_points:
        raise ValueError("A face bounding box and eye landmarks are required")
    face_x, face_y, face_width, face_height = face_bounding_box
    image_points = [
        (face_x + point[0] * face_width, face_y + point[1] * face_height)
        for point in eye_points
    ]
    minimum_x = min(point[0] for point in image_points)
    maximum_x = max(point[0] for point in image_points)
    minimum_y = min(point[1] for point in image_points)
    maximum_y = max(point[1] for point in image_points)
    width = maximum_x - minimum_x
    height = (maximum_y - minimum_y) * 0.25
    if width < 0.02 or height < 0.004:
        raise ValueError("The conjunctiva region is too small")
    return minimum_x, minimum_y, width, height
